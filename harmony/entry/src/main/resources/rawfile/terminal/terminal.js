'use strict';
const term = new Terminal({cursorBlink:true, scrollback:5000, fontSize:14, fontFamily:'monospace', theme:{background:'#101216', foreground:'#F1F3F5'}, logLevel:'off', allowProposedApi:false});
const fit = new FitAddon.FitAddon();
term.loadAddon(fit);
term.open(document.getElementById('terminal'));
const terminal = document.getElementById('terminal');
let scrollbarTimer;
let headerInset = 8;
let alternateScroll = 0;
let fitFrame = 0;
function scheduleFit() {
  if (fitFrame) return;
  fitFrame = requestAnimationFrame(() => { fitFrame = 0; fit.fit(); });
}
function updateHeaderInset() {
  const row = terminal.querySelector('.xterm-rows>div');
  const rowHeight = row ? row.getBoundingClientRect().height : term.options.fontSize * term.options.lineHeight;
  const buffer = term.buffer.active;
  const distance = buffer.type === 'alternate' ? alternateScroll : (buffer.baseY - buffer.viewportY) * rowHeight;
  const inset = Math.max(8, headerInset - Math.max(0, distance));
  if (Math.abs(parseFloat(terminal.style.getPropertyValue('--top-inset') || '8') - inset) < 0.5) return;
  terminal.style.setProperty('--top-inset', inset + 'px');
  scheduleFit();
}
function scrollAlternate(pixels) {
  if (term.buffer.active.type !== 'alternate') return;
  alternateScroll = Math.max(0, Math.min(headerInset - 8, alternateScroll - pixels));
  updateHeaderInset();
}
term.onScroll(() => {
  terminal.classList.add('scrolling');
  clearTimeout(scrollbarTimer);
  scrollbarTimer = setTimeout(() => terminal.classList.remove('scrolling'), 160);
  updateHeaderInset();
});
term.buffer.onBufferChange(() => { alternateScroll = 0; updateHeaderInset(); });
terminal.addEventListener('wheel', event => {
  scrollAlternate(event.deltaY * (event.deltaMode === 1 ? term.options.fontSize * term.options.lineHeight : 1));
}, {passive:true, capture:true});
// ArkWeb touch events scroll the terminal buffer through its public API.
let touchY = 0;
terminal.addEventListener('touchstart', event => {
  if (event.touches.length === 1) touchY = event.touches[0].clientY;
}, {passive:true});
terminal.addEventListener('touchmove', event => {
  if (event.touches.length !== 1) return;
  const rowHeight = terminal.querySelector('.xterm-screen').clientHeight / term.rows;
  const lines = Math.trunc((touchY - event.touches[0].clientY) / rowHeight);
  if (lines) { scrollAlternate(lines * rowHeight); term.scrollLines(lines); touchY -= lines * rowHeight; }
  event.preventDefault();
  event.stopPropagation();
}, {passive:false});
term.onData(data => { if(window.uuTerminal) window.uuTerminal.input(data); });
term.onResize(size => { if(window.uuTerminal) window.uuTerminal.resize(size.cols, size.rows); });
new ResizeObserver(scheduleFit).observe(terminal);
window.uuWrite = data => { term.write(data); };
window.uuReset = data => { alternateScroll = 0; term.reset(); term.write(data, updateHeaderInset); };
window.uuFit = () => { fit.fit(); if(window.uuTerminal) window.uuTerminal.resize(term.cols, term.rows); };
window.uuSetTopInset = inset => { headerInset = Math.max(8, inset); updateHeaderInset(); };
window.uuReady = () => { fit.fit(); term.focus(); };
// Keep terminal output and OSC links inside the local view.
document.addEventListener('click', event => { if(event.target.closest('a')) event.preventDefault(); });
