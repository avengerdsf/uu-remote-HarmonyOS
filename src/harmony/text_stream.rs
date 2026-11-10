//! Preserve UTF-8 characters split across terminal frames.
#[derive(Default)]
pub struct Utf8Stream { pending: Vec<u8> }
impl Utf8Stream {
    pub fn push(&mut self, bytes: &[u8]) -> String {
        self.pending.extend_from_slice(bytes);
        let mut output = String::new();
        let mut offset = 0;
        while offset < self.pending.len() {
            match std::str::from_utf8(&self.pending[offset..]) {
                Ok(text) => { output.push_str(text); offset = self.pending.len(); }
                Err(error) => {
                    let end = offset + error.valid_up_to();
                    output.push_str(std::str::from_utf8(&self.pending[offset..end]).unwrap());
                    offset = end;
                    match error.error_len() {
                        Some(length) => { output.push('\u{fffd}'); offset += length; }
                        None => break,
                    }
                }
            }
        }
        self.pending.drain(..offset);
        output
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn split_unicode_and_escape_sequences() {
        let input = "中文😀\x1b[31mred\x1b[0m";
        let mut stream = Utf8Stream::default();
        let output: String = input.as_bytes().iter().map(|byte| stream.push(&[*byte])).collect();
        assert_eq!(output, input);
        assert!(stream.pending.is_empty());
    }
    #[test]
    fn malformed_bytes_do_not_discard_following_text() {
        let mut stream = Utf8Stream::default();
        assert_eq!(stream.push(&[0xff, b'a', 0xe4]), "�a");
        assert_eq!(stream.push(&[0xb8, 0xad]), "中");
    }
}
