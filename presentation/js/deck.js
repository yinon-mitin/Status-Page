(() => {
  'use strict';

  const deck = document.getElementById('deck');
  const slides = Array.from(deck.querySelectorAll('.slide'));
  const storageKey = 'status-page-presentation-slide';
  let current = 0;
  let touchStartX = null;
  let touchStartY = null;

  const chrome = document.createElement('nav');
  chrome.id = 'chrome';
  chrome.setAttribute('aria-label', 'Presentation controls');
  chrome.innerHTML = `
    <button id="prev-slide" type="button" aria-label="Previous slide" title="Previous (←)">←</button>
    <div id="slide-counter" aria-label="Slide number"><span>1</span><i>/</i><b>${slides.length}</b></div>
    <button id="next-slide" type="button" aria-label="Next slide" title="Next (→ or Space)">→</button>
    <button id="notes-toggle" type="button" aria-label="Toggle presenter notes" aria-pressed="false" title="Presenter notes (N)">Notes</button>
    <button id="fullscreen-toggle" type="button" aria-label="Toggle fullscreen" title="Fullscreen (F)">Full</button>
    <button id="help-toggle" type="button" aria-label="Keyboard help" title="Keyboard help (?)">?</button>`;

  const progress = document.createElement('button');
  progress.id = 'progress';
  progress.type = 'button';
  progress.setAttribute('aria-label', 'Jump through slides');
  progress.innerHTML = '<span></span>';

  const sourceChip = document.createElement('div');
  sourceChip.id = 'source-chip';

  const notesPanel = document.createElement('aside');
  notesPanel.id = 'notes-panel';
  notesPanel.setAttribute('aria-label', 'Presenter notes');
  notesPanel.setAttribute('aria-hidden', 'true');
  notesPanel.innerHTML = `
    <header><div><span>Presenter notes</span><strong id="notes-title"></strong></div><button id="notes-close" type="button" aria-label="Close presenter notes">×</button></header>
    <div id="notes-content"></div>
    <footer><kbd>N</kbd> notes <span></span> <kbd>←</kbd><kbd>→</kbd> navigate <span></span> <kbd>F</kbd> fullscreen</footer>`;

  const help = document.createElement('aside');
  help.id = 'help';
  help.setAttribute('aria-label', 'Keyboard shortcuts');
  help.innerHTML = `
    <strong>Keyboard controls</strong>
    <span><kbd>→</kbd> <kbd>Space</kbd> Next slide</span>
    <span><kbd>←</kbd> Previous slide</span>
    <span><kbd>Home</kbd> First slide</span>
    <span><kbd>End</kbd> Last slide</span>
    <span><kbd>N</kbd> Presenter notes</span>
    <span><kbd>F</kbd> Fullscreen</span>
    <span><kbd>P</kbd> Print / PDF</span>
    <span><kbd>?</kbd> This help</span>`;

  document.body.append(chrome, progress, sourceChip, notesPanel, help);

  const prevButton = document.getElementById('prev-slide');
  const nextButton = document.getElementById('next-slide');
  const notesButton = document.getElementById('notes-toggle');
  const fullscreenButton = document.getElementById('fullscreen-toggle');
  const helpButton = document.getElementById('help-toggle');
  const notesClose = document.getElementById('notes-close');
  const counterCurrent = document.querySelector('#slide-counter span');
  const progressFill = progress.querySelector('span');
  const notesTitle = document.getElementById('notes-title');
  const notesContent = document.getElementById('notes-content');

  function fitDeck() {
    const scale = Math.min(window.innerWidth / 1920, window.innerHeight / 1080);
    deck.style.transform = `translate(-50%, -50%) scale(${scale})`;
  }

  function indexFromHash() {
    const id = decodeURIComponent(window.location.hash.slice(1));
    return slides.findIndex((slide) => slide.id === id);
  }

  function initialIndex() {
    const hashIndex = indexFromHash();
    if (hashIndex >= 0) return hashIndex;
    const saved = Number.parseInt(localStorage.getItem(storageKey), 10);
    return Number.isInteger(saved) && saved >= 0 && saved < slides.length ? saved : 0;
  }

  function renderNotes(slide) {
    const notes = slide.querySelector('.speaker-notes');
    notesTitle.textContent = slide.dataset.title || `Slide ${current + 1}`;
    notesContent.innerHTML = notes ? notes.innerHTML : '<p>No notes for this slide.</p>';
  }

  function show(index, direction = 1, updateHash = true) {
    const next = Math.max(0, Math.min(index, slides.length - 1));
    const previous = current;
    current = next;

    slides.forEach((slide, slideIndex) => {
      slide.classList.remove('active', 'enter-forward', 'enter-back');
      slide.setAttribute('aria-hidden', slideIndex === current ? 'false' : 'true');
    });

    const active = slides[current];
    active.classList.add('active');
    if (current !== previous) {
      active.classList.add(direction >= 0 ? 'enter-forward' : 'enter-back');
    }

    counterCurrent.textContent = String(current + 1);
    progressFill.style.width = `${((current + 1) / slides.length) * 100}%`;
    prevButton.disabled = current === 0;
    nextButton.disabled = current === slides.length - 1;
    sourceChip.textContent = `Source: ${active.dataset.source || 'repository source'}`;
    document.title = `${current + 1}/${slides.length} · ${active.dataset.title} — Status-Page on AWS`;
    localStorage.setItem(storageKey, String(current));
    renderNotes(active);

    if (updateHash) {
      history.replaceState(null, '', `#${active.id}`);
    }
  }

  function next() { show(current + 1, 1); }
  function previous() { show(current - 1, -1); }

  function toggleNotes(force) {
    const open = typeof force === 'boolean' ? force : !document.body.classList.contains('notes-open');
    document.body.classList.toggle('notes-open', open);
    notesPanel.setAttribute('aria-hidden', String(!open));
    notesButton.setAttribute('aria-pressed', String(open));
  }

  async function toggleFullscreen() {
    try {
      if (!document.fullscreenElement) {
        await document.documentElement.requestFullscreen();
      } else {
        await document.exitFullscreen();
      }
    } catch (error) {
      console.warn('Fullscreen request was rejected:', error);
    }
  }

  function toggleHelp(force) {
    const open = typeof force === 'boolean' ? force : !help.classList.contains('visible');
    help.classList.toggle('visible', open);
  }

  prevButton.addEventListener('click', previous);
  nextButton.addEventListener('click', next);
  notesButton.addEventListener('click', () => toggleNotes());
  notesClose.addEventListener('click', () => toggleNotes(false));
  fullscreenButton.addEventListener('click', toggleFullscreen);
  helpButton.addEventListener('click', () => toggleHelp());

  progress.addEventListener('click', (event) => {
    const rect = progress.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
    const target = Math.min(slides.length - 1, Math.floor(ratio * slides.length));
    show(target, target >= current ? 1 : -1);
  });

  deck.addEventListener('click', (event) => {
    if (event.target.closest('a, button')) return;
    const rect = deck.getBoundingClientRect();
    const localX = event.clientX - rect.left;
    if (localX < rect.width * 0.18) previous();
    else if (localX > rect.width * 0.82) next();
  });

  document.addEventListener('keydown', (event) => {
    if (event.target.matches('input, textarea, select, button')) return;
    switch (event.key) {
      case 'ArrowRight':
      case 'PageDown':
      case ' ':
        event.preventDefault(); next(); break;
      case 'ArrowLeft':
      case 'PageUp':
        event.preventDefault(); previous(); break;
      case 'Home':
        event.preventDefault(); show(0, -1); break;
      case 'End':
        event.preventDefault(); show(slides.length - 1, 1); break;
      case 'n':
      case 'N':
        toggleNotes(); break;
      case 'f':
      case 'F':
        toggleFullscreen(); break;
      case 'p':
      case 'P':
        window.print(); break;
      case '?':
        toggleHelp(); break;
      case 'Escape':
        toggleHelp(false);
        if (!document.fullscreenElement) toggleNotes(false);
        break;
      default:
        break;
    }
  });

  deck.addEventListener('touchstart', (event) => {
    if (event.touches.length !== 1) return;
    touchStartX = event.touches[0].clientX;
    touchStartY = event.touches[0].clientY;
  }, { passive: true });

  deck.addEventListener('touchend', (event) => {
    if (touchStartX === null || touchStartY === null || !event.changedTouches.length) return;
    const dx = event.changedTouches[0].clientX - touchStartX;
    const dy = event.changedTouches[0].clientY - touchStartY;
    touchStartX = null;
    touchStartY = null;
    if (Math.abs(dx) < 55 || Math.abs(dx) < Math.abs(dy) * 1.25) return;
    if (dx < 0) next(); else previous();
  }, { passive: true });

  window.addEventListener('resize', fitDeck);
  window.addEventListener('hashchange', () => {
    const index = indexFromHash();
    if (index >= 0 && index !== current) show(index, index >= current ? 1 : -1, false);
  });

  current = initialIndex();
  fitDeck();
  show(current, 1, !window.location.hash);
})();
