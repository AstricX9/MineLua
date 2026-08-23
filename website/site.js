/* The whole atmosphere runs off one number.

   --t is 0 at the top of the page and 1 at the bottom. The backdrop layers read
   it directly in CSS, so scrolling carries the page from sunset into night and
   brings the stars up as it goes. Written on a rAF so the scroll handler never
   does layout work itself. */

(function () {
  var root = document.documentElement;
  var queued = false;

  function apply() {
    queued = false;
    var max = document.body.scrollHeight - window.innerHeight;
    var t = max > 0 ? window.scrollY / max : 0;
    root.style.setProperty('--t', Math.min(1, Math.max(0, t)).toFixed(4));
  }

  function request() {
    if (!queued) {
      queued = true;
      requestAnimationFrame(apply);
    }
  }

  addEventListener('scroll', request, { passive: true });
  addEventListener('resize', request);
  addEventListener('load', apply);
  apply();
})();
