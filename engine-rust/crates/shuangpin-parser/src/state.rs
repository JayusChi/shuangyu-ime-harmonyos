/// Coarse state of the parser state machine.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ParserState {
    /// No raw input is buffered.
    Empty,
    /// The parser has buffered input and is composing.
    Composing,
    /// The trailing key is waiting for a second key.
    Incomplete,
    /// All buffered keys currently form complete syllables.
    CompleteSequence,
    /// The buffered input contains an invalid key or code.
    Invalid,
}
