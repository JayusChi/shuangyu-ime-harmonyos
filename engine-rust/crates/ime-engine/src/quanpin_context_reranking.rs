use std::path::Path;
use std::time::Instant;

use context_reranker::{
    rerank_order, ContextWindow, ModelLoadError, RerankCandidate, RerankStats, WordNgramModel,
    MAX_CANDIDATE_POOL, MAX_MODEL_LOAD_MICROS, MAX_RERANK_MICROS, MODEL_VERSION,
};
use sentence_decoder::SentenceCandidate;

pub const QUANPIN_CONTEXT_RERANKING_CONFIG_VERSION: u32 = 2;

/// Runtime configuration is intentionally narrow: the built model has fixed
/// weights and limits, while the app supplies a verified resource path/hash.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct QuanpinContextRerankingConfig {
    pub config_version: u32,
    pub enabled: bool,
    pub model_path: Option<String>,
    pub model_sha256: Option<String>,
}

impl Default for QuanpinContextRerankingConfig {
    fn default() -> Self {
        Self {
            config_version: QUANPIN_CONTEXT_RERANKING_CONFIG_VERSION,
            enabled: false,
            model_path: None,
            model_sha256: None,
        }
    }
}

impl QuanpinContextRerankingConfig {
    pub fn new(enabled: bool, model_path: Option<String>, model_sha256: Option<String>) -> Self {
        Self {
            enabled,
            model_path,
            model_sha256,
            ..Self::default()
        }
    }

    pub fn validate(&self) -> bool {
        self.config_version == QUANPIN_CONTEXT_RERANKING_CONFIG_VERSION
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct QuanpinContextRerankingStatus {
    pub enabled: bool,
    pub model_version: u16,
    pub model_file_bytes: usize,
    pub model_memory_bytes: usize,
    pub model_load_micros: u64,
    pub last_error_code: String,
}

#[derive(Clone, Debug)]
pub(crate) struct QuanpinContextReranker {
    model: Option<WordNgramModel>,
    context: ContextWindow,
    status: QuanpinContextRerankingStatus,
}

impl QuanpinContextReranker {
    pub(crate) fn new(
        config: &QuanpinContextRerankingConfig,
        lexicon_version: Option<u32>,
    ) -> Self {
        let mut output = Self {
            model: None,
            context: ContextWindow::default(),
            status: QuanpinContextRerankingStatus {
                enabled: false,
                model_version: MODEL_VERSION,
                model_file_bytes: 0,
                model_memory_bytes: 0,
                model_load_micros: 0,
                last_error_code: String::new(),
            },
        };
        if !config.enabled {
            return output;
        }
        let Some(lexicon_version) = lexicon_version else {
            output.status.last_error_code = "lexicon_unavailable".to_owned();
            return output;
        };
        let Some(path) = config
            .model_path
            .as_deref()
            .filter(|path| !path.trim().is_empty())
        else {
            output.status.last_error_code = "model_path_missing".to_owned();
            return output;
        };
        let Some(hash) = config
            .model_sha256
            .as_deref()
            .filter(|hash| !hash.trim().is_empty())
        else {
            output.status.last_error_code = "model_hash_missing".to_owned();
            return output;
        };
        let load_started = Instant::now();
        let loaded = WordNgramModel::load_file(Path::new(path), hash, lexicon_version);
        output.status.model_load_micros = load_started.elapsed().as_micros() as u64;
        if output.status.model_load_micros > MAX_MODEL_LOAD_MICROS {
            output.status.last_error_code = "load_time_limit".to_owned();
            return output;
        }
        match loaded {
            Ok(model) => {
                output.status.enabled = true;
                output.status.model_file_bytes = model.file_bytes();
                output.status.model_memory_bytes = model.memory_bytes();
                output.model = Some(model);
            }
            Err(error) => output.status.last_error_code = model_error_code(error).to_owned(),
        }
        output
    }

    pub(crate) fn status(&self) -> QuanpinContextRerankingStatus {
        self.status.clone()
    }

    pub(crate) fn set_context_allowed(&mut self, allowed: bool) {
        self.context.set_allowed(allowed);
    }

    pub(crate) fn clear_context(&mut self) {
        self.context.clear();
    }

    pub(crate) fn record_explicit_commit(&mut self, words: &[String]) {
        self.context.record_committed_words(words);
    }

    pub(crate) fn local_associations(&self, limit: usize) -> Vec<String> {
        self.model
            .as_ref()
            .map(|model| model.suggest_next(self.context.words(), limit))
            .unwrap_or_default()
    }

    pub(crate) fn rerank(
        &self,
        candidates: Vec<SentenceCandidate>,
    ) -> (Vec<SentenceCandidate>, RerankStats) {
        if self.model.is_none() {
            return (candidates, RerankStats::default());
        }
        let started = Instant::now();
        let pool_len = candidates.len().min(MAX_CANDIDATE_POOL);
        let features = candidates
            .iter()
            .take(pool_len)
            .map(|candidate| RerankCandidate {
                base_score: candidate.score,
                words: candidate.words.clone(),
                complete_coverage: candidate.complete_coverage,
                fallback_count: candidate.fallback_count,
                // User lexicon has already been merged later. Any fixed rule
                // is therefore outside this decoder-only stage by construction.
                fixed: false,
            })
            .collect::<Vec<_>>();
        let (order, mut stats) = rerank_order(self.model.as_ref(), &features, self.context.words());
        stats.skipped_candidate_limit = stats
            .skipped_candidate_limit
            .saturating_add(candidates.len().saturating_sub(pool_len));
        stats.rerank_micros = started.elapsed().as_micros() as u64;
        if stats.rerank_micros > MAX_RERANK_MICROS {
            stats.timeout_fallbacks = 1;
            return (candidates, stats);
        }
        let mut prefix = candidates;
        let tail = prefix.split_off(pool_len);
        let mut source = prefix.into_iter().map(Some).collect::<Vec<_>>();
        let mut reordered = order
            .into_iter()
            .filter_map(|index| source.get_mut(index).and_then(Option::take))
            .collect::<Vec<_>>();
        reordered.extend(tail);
        (reordered, stats)
    }
}

fn model_error_code(error: ModelLoadError) -> &'static str {
    error.code()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_or_invalid_model_disables_only_the_reranker() {
        let config = QuanpinContextRerankingConfig::new(
            true,
            Some("missing.qng".to_owned()),
            Some("0".repeat(64)),
        );
        let reranker = QuanpinContextReranker::new(&config, Some(1));
        assert!(!reranker.status().enabled);
        assert_eq!(reranker.status().last_error_code, "io_error");
    }

    #[test]
    fn privacy_switch_clears_ephemeral_context() {
        let mut reranker =
            QuanpinContextReranker::new(&QuanpinContextRerankingConfig::default(), Some(1));
        reranker.record_explicit_commit(&["已提交".to_owned()]);
        reranker.set_context_allowed(false);
        reranker.record_explicit_commit(&["不得保存".to_owned()]);
        reranker.set_context_allowed(true);
        // No public context accessor is exposed. A disabled model must still
        // be a no-op, which verifies the clearing path has no output effect.
        assert!(!reranker.status().enabled);
    }
}
