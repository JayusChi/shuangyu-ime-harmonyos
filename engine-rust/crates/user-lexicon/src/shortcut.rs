/// Only data URIs supported by the OS launchers are accepted; never commands.
pub fn valid_shortcut_target(action: &str, target: &str) -> bool {
    if target.is_empty()
        || target.len() > 2048
        || target.chars().any(|c| c.is_control() || c == '\\')
    {
        return false;
    }
    match action {
        "url.open" => {
            if target.chars().any(char::is_whitespace) {
                return false;
            }
            let Some(rest) = target
                .strip_prefix("https://")
                .or_else(|| target.strip_prefix("http://"))
            else {
                return false;
            };
            let authority = rest.split(['/', '?', '#']).next().unwrap_or_default();
            !authority.is_empty() && !authority.contains('@') && !authority.starts_with(':')
        }
        "directory.open" => {
            target.starts_with("file://docs/") && target.len() > "file://docs/".len()
        }
        _ => false,
    }
}
