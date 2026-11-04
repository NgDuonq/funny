// Executed only on explicitly supported music sites. No network requests or page mutation on reads.
(function (command, expectedTrack, seekTime) {
  const host = location.hostname;
  const allowed = ['soundcloud.com', 'www.soundcloud.com', 'youtube.com', 'www.youtube.com',
    'music.youtube.com', 'open.spotify.com', 'music.apple.com'];
  if (!allowed.includes(host)) return '';
  const q = s => document.querySelector(s);
  const text = s => (q(s)?.textContent || '').trim();
  const media = [...document.querySelectorAll('audio,video')].find(m => !m.paused && !m.ended)
    || [...document.querySelectorAll('audio,video')].find(m => m.currentSrc || m.src);
  const meta = navigator.mediaSession?.metadata;
  const sc = host.endsWith('soundcloud.com');
  const yt = host.endsWith('youtube.com');
  const sp = host === 'open.spotify.com';
  const selectors = sc ? {
    toggle: '.playControls__play', next: '.playControls__next', previous: '.playControls__prev'
  } : yt ? {
    toggle: '.ytp-play-button, #play-pause-button', next: '.ytp-next-button, .next-button',
    previous: '.ytp-prev-button, .previous-button'
  } : sp ? {
    toggle: '[data-testid="control-button-playpause"]', next: '[data-testid="control-button-skip-forward"]',
    previous: '[data-testid="control-button-skip-back"]'
  } : { toggle: '[data-testid="play-pause"]', next: '[data-testid="next"]', previous: '[data-testid="previous"]' };
  const title = (meta?.title || (sc ? text('.playbackSoundBadge__titleLink') :
    yt ? text('h1.ytd-watch-metadata yt-formatted-string, .title.ytmusic-player-bar') :
    sp ? text('[data-testid="context-item-info-title"]') : '')).trim();
  // Do not turn a browsing page, an advert or an unrelated video into a music source.
  if (!title || (!media && !q(selectors.toggle))) return '';
  const artist = (meta?.artist || (sc ? text('.playbackSoundBadge__lightLink') :
    yt ? text('#owner #channel-name, .byline.ytmusic-player-bar') :
    sp ? text('[data-testid="context-item-info-subtitles"]') : '')).trim();
  const track = location.href.split('#')[0] + '|' + title + '|' + artist;
  const toggle = q(selectors.toggle);
  const playing = media ? !media.paused && !media.ended :
    sc ? !!toggle?.classList.contains('playing') : navigator.mediaSession?.playbackState === 'playing';
  const finite = n => Number.isFinite(n) && n >= 0 ? n : 0;
  const duration = finite(media?.duration);
  const canSeek = !!media && duration > 0 && !!media.seekable?.length;
  const artwork = meta?.artwork?.slice(-1)[0]?.src || '';
  const enabled = el => !!el && !el.disabled && el.getAttribute('aria-disabled') !== 'true';
  if (command !== 'read') {
    if (track !== expectedTrack) return 'stale';
    if (command === 'seek') {
      if (!canSeek) return 'unsupported';
      media.currentTime = Math.min(duration, Math.max(0, seekTime)); return 'ok';
    }
    const button = q(selectors[command] || 'nonexistent-element');
    if (enabled(button)) { button.click(); return 'ok'; }
    if (command === 'toggle' && media) {
      if (media.paused) { const p = media.play(); if (p?.catch) p.catch(() => {}); }
      else media.pause();
      return 'ok';
    }
    return 'unsupported';
  }
  return JSON.stringify({track, title, artist, duration, position: finite(media?.currentTime), playing,
    artwork, canSeek, canToggle: enabled(toggle) || !!media,
    canNext: enabled(q(selectors.next)), canPrevious: enabled(q(selectors.previous))});
})
