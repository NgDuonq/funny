const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const code = fs.readFileSync('Sources/MusicIsland/Resources/WebPlayer.js', 'utf8');
function fixture({host='www.youtube.com', media, selectors={}, meta={title:'A song',artist:'Artist'}, state='paused'}={}) {
  const context = {location:{hostname:host,href:'https://'+host+'/watch?v=123'},
    navigator:{mediaSession:{metadata:meta,playbackState:state}},
    document:{querySelector:s=>selectors[s]||null,querySelectorAll:()=>media?[media]:[]}};
  return vm.runInNewContext(code,context);
}
function audio(overrides={}) {return {paused:false,ended:false,currentSrc:'audio',currentTime:12,duration:200,
  seekable:{length:1},pause(){this.paused=true},play(){this.paused=false;return Promise.resolve()},...overrides};}
test('HTML media metadata, progress, seek, and stale track rejection',()=>{
  const media=audio();const run=fixture({media});const s=JSON.parse(run('read'));
  assert.equal(s.playing,true);assert.equal(s.canSeek,true);assert.equal(s.position,12);
  assert.equal(run('seek',s.track,300),'ok');assert.equal(media.currentTime,200);
  assert.equal(run('toggle','old track',0),'stale');assert.equal(media.paused,false);
  assert.equal(run('toggle',s.track,0),'ok');assert.equal(media.paused,true);
});
test('SoundCloud fallback works without exposed media element',()=>{
  let clicks=0;const play={classList:{contains:()=>true},getAttribute:()=>null,click:()=>clicks++};
  const next={getAttribute:()=>null,click:()=>clicks++};
  const run=fixture({host:'soundcloud.com',meta:null,selectors:{
    '.playControls__play':play,'.playControls__next':next,
    '.playbackSoundBadge__titleLink':{textContent:'Hà Nội'},'.playbackSoundBadge__lightLink':{textContent:'Artist'}}});
  const s=JSON.parse(run('read'));assert.equal(s.title,'Hà Nội');assert.equal(s.playing,true);
  assert.equal(s.canSeek,false);assert.equal(s.canNext,true);assert.equal(s.canPrevious,false);
  assert.equal(run('next',s.track),'ok');assert.equal(clicks,1);
  assert.equal(run('seek',s.track,12),'unsupported');
});
test('unsupported hosts and empty browsing pages are ignored',()=>{
  assert.equal(fixture({host:'soundcloud.com.evil.example',media:audio()})('read'),'');
  assert.equal(fixture({meta:null})('read'),'');
});
test('live stream has no seek and disabled buttons stay disabled',()=>{
  const media=audio({duration:Infinity,seekable:{length:0}});
  const run=fixture({media,selectors:{'.ytp-next-button, .next-button':{disabled:true,getAttribute:()=>null}}});
  const s=JSON.parse(run('read'));assert.equal(s.duration,0);assert.equal(s.canSeek,false);assert.equal(s.canNext,false);
  assert.equal(run('next',s.track),'unsupported');
});
