//! Shared clipboard negotiation for native controllers.
use super::wire;
use crate::{clipboard_protocol as text,clipboard_rich as rich,protocol::{decode_wire,WireValue}};
use text::MAX_TEXT;

#[derive(Default)]
// target_mac: Some(true) official Mac host, Some(false) Windows-type host (official or this project), None unknown.
pub(crate) struct SyncState {pub(crate) last:Option<String>,pub(crate) assembly:text::Assembly,pub(crate) rich:rich::State,pub(crate) seq:u64,pub(crate) target_mac:Option<bool>}
impl SyncState {
    fn next(&mut self)->u64{self.seq=self.seq.wrapping_add(1).max(100);self.seq}
    /// Two requests per change: the rich format-list offer (this project's host asks for the data) and
    /// RpcRequest case 10 ClipboardTextChangeRequest carrying the text, which the official Windows host applies
    /// (handle_text_change_request -> notifyReceiveText); it only acknowledges the rich offer. Each host
    /// ignores the other form.
    pub(crate) fn local(&mut self,value:String)->Result<Option<Vec<Vec<u8>>>,&'static str>{
        if self.last.as_ref()==Some(&value){return Ok(None)}
        let id=self.next();let payload=self.rich.offer_any_host(id,value.clone())?;
        let rich=wire::envelope(self.next(),21,&payload);
        let text=wire::envelope(self.next(),21,&crate::clipboard_protocol::text_request(self.next(),&value));
        self.last=Some(value);
        // Live-verified: the official Windows host writes case-10 text, then a rich format list replaces it with a
        // placeholder it never asks us to render (paste is empty). The Mac host only takes the rich offer.
        Ok(Some(match self.target_mac {Some(true)=>vec![rich],Some(false)=>vec![text],None=>vec![rich,text]}))
    }
    pub(crate) fn receive(&mut self,data:&[u8])->Result<(Vec<Vec<u8>>,Option<String>),&'static str>{
        if data.len()>MAX_TEXT*2+1024{return Err("clipboard message exceeds limit")}
        let fields=decode_wire(data).map_err(|_|"invalid clipboard envelope")?;
        let mut replies=Vec::new();let mut value=None;
        for field in fields {
            let WireValue::Bytes(payload)=field.value else{continue};
            match field.number {
                17=>if let Some(text)=self.assembly.accept(payload)?{value=Some(text)},
                21=>{
                    let seq=&mut self.seq;
                    let result=self.rich.request(payload,&mut ||{*seq=seq.wrapping_add(1).max(100);*seq})?;
                    if result.text.is_some(){value=result.text;}
                    for (kind,body) in result.messages {replies.push(wire::envelope(self.next(),kind,&body));}
                    if let Some((header,text))=text::read_text_request(payload)?{
                        value=Some(text);replies.push(wire::envelope(self.next(),22,&text::text_response(&header)));
                    }
                },
                22=>{
                    // TextChangeResponse (case 6 {1 err}, CB_SUCCEEDED=1) answers our case 10 request: status only.
                    if let Some(status)=decode_wire(payload).ok().and_then(|f|f.into_iter().find_map(|x|match (x.number,x.value){(6,WireValue::Bytes(b))=>Some(b.to_vec()),_=>None})){
                        let err=decode_wire(&status).ok().and_then(|f|f.into_iter().find_map(|x|match (x.number,x.value){(1,WireValue::Varint(v))=>Some(v),_=>None})).unwrap_or(0);
                        log::info!("Viewer clipboard text change acknowledged: err={err}");
                    }
                    if let Some(text)=self.rich.response(payload)?{value=Some(text)}
                },
                _=>{},
            }
        }
        if value.as_ref().is_some_and(|text|text.contains('\0')){return Err("clipboard text contains NUL")}
        Ok((replies,value))
    }
}
