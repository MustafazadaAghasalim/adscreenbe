/* Adscreen Belgium — landing interactivity
 *  - Language toggle (NL / FR / EN) swaps copy in-place
 *  - Email signup form: client-side validation + friendly status message
 *    (no backend wired — captures intent only; replace with a real endpoint
 *    when the launch list is ready)
 */
(function () {
  'use strict';

  const I18N = {
    nl: {
      eyebrow: 'België · 2026',
      'title-1': 'Binnenkort',
      'title-2': 'in België',
      lede:
        'Interactieve advertenties op het scherm in elke taxi en rideshare — binnenkort in Brussel, Antwerpen en daarbuiten.',
      'meta-launch': 'Lancering',
      'meta-cities': 'Steden',
      'meta-fleet': 'Doel',
      'email-label': 'E-mail',
      cta: 'Hou me op de hoogte',
      'feat-1-title': 'Live in elke rit',
      'feat-1-body':
        'Centraal beheerd vanaf één dashboard. Bedrijven plannen campagnes, chauffeurs zien niets behalve de rit.',
      'feat-2-title': 'Lokale targeting',
      'feat-2-body':
        'Geofencing per stad en buurt. Een spot in Brussel Centrum is anders dan een spot bij Antwerpen Centraal.',
      'feat-3-title': 'Drietalig, by design',
      'feat-3-body':
        'Nederlands, Frans en Engels — content schakelt mee met het publiek.',
      'signals-label': 'Een nieuw hoofdstuk van',
      'footer-meta': '© 2026 · Brussel · contact@adscreen.be',
      'status-invalid': 'Voer een geldig e-mailadres in.',
      'status-ok': 'Bedankt — we houden je op de hoogte.',
      placeholder: 'jij@bedrijf.be'
    },
    fr: {
      eyebrow: 'Belgique · 2026',
      'title-1': 'Bientôt',
      'title-2': 'en Belgique',
      lede:
        'Publicité interactive à bord de chaque taxi et rideshare — prochainement à Bruxelles, Anvers et au-delà.',
      'meta-launch': 'Lancement',
      'meta-cities': 'Villes',
      'meta-fleet': 'Objectif',
      'email-label': 'E-mail',
      cta: 'Tenez-moi au courant',
      'feat-1-title': 'En direct dans chaque course',
      'feat-1-body':
        'Tout est piloté depuis un seul tableau de bord. Les marques planifient, les chauffeurs ne voient que la course.',
      'feat-2-title': 'Ciblage local',
      'feat-2-body':
        'Geofencing par ville et par quartier. Un spot au centre de Bruxelles n’est pas un spot à Anvers-Central.',
      'feat-3-title': 'Trilingue, par conception',
      'feat-3-body':
        'Néerlandais, français et anglais — le contenu suit le public.',
      'signals-label': 'Un nouveau chapitre de',
      'footer-meta': '© 2026 · Bruxelles · contact@adscreen.be',
      'status-invalid': 'Veuillez saisir une adresse e-mail valide.',
      'status-ok': 'Merci — nous vous tiendrons au courant.',
      placeholder: 'toi@entreprise.be'
    },
    en: {
      eyebrow: 'Belgium · 2026',
      'title-1': 'Coming soon',
      'title-2': 'to Belgium',
      lede:
        'In-screen interactive advertising in every taxi and rideshare — coming to Brussels, Antwerp, and beyond.',
      'meta-launch': 'Launch',
      'meta-cities': 'Cities',
      'meta-fleet': 'Fleet target',
      'email-label': 'Email',
      cta: 'Keep me posted',
      'feat-1-title': 'Live in every ride',
      'feat-1-body':
        'Run from a single dashboard. Brands plan campaigns; drivers see nothing but the ride.',
      'feat-2-title': 'Local targeting',
      'feat-2-body':
        'Geofencing per city and per neighborhood. A spot in Brussels-Centre is different from one at Antwerp-Central.',
      'feat-3-title': 'Trilingual by design',
      'feat-3-body':
        'Dutch, French, and English — content follows the audience.',
      'signals-label': 'A new chapter of',
      'footer-meta': '© 2026 · Brussels · contact@adscreen.be',
      'status-invalid': 'Please enter a valid email address.',
      'status-ok': 'Thanks — we’ll keep you posted.',
      placeholder: 'you@company.be'
    }
  };

  const langButtons = document.querySelectorAll('.lang-btn');
  const i18nNodes = document.querySelectorAll('[data-i18n]');
  const emailInput = document.getElementById('email');
  const statusEl = document.getElementById('signup-status');
  const form = document.getElementById('signup');

  let activeLang = 'nl';

  function applyLanguage(lang) {
    const dict = I18N[lang];
    if (!dict) return;
    activeLang = lang;
    document.documentElement.lang = lang === 'en' ? 'en' : lang + '-BE';

    i18nNodes.forEach((node) => {
      const key = node.getAttribute('data-i18n');
      if (key && dict[key] !== undefined) node.textContent = dict[key];
    });

    if (emailInput) emailInput.placeholder = dict.placeholder;

    langButtons.forEach((btn) => {
      const isActive = btn.dataset.lang === lang;
      btn.classList.toggle('is-active', isActive);
      btn.setAttribute('aria-selected', String(isActive));
    });

    try {
      localStorage.setItem('adscreen-lang', lang);
    } catch (_) {}
  }

  langButtons.forEach((btn) => {
    btn.addEventListener('click', () => applyLanguage(btn.dataset.lang));
  });

  // Restore preferred language: storage > <html lang> > NL
  let initial = 'nl';
  try {
    const saved = localStorage.getItem('adscreen-lang');
    if (saved && I18N[saved]) initial = saved;
  } catch (_) {}
  if (initial === 'nl' && /^en/.test(navigator.language || '')) initial = 'en';
  else if (initial === 'nl' && /^fr/.test(navigator.language || '')) initial = 'fr';
  applyLanguage(initial);

  // ── Email signup ──
  function setStatus(text, kind) {
    if (!statusEl) return;
    statusEl.textContent = text;
    statusEl.classList.remove('ok', 'err');
    if (kind) statusEl.classList.add(kind);
  }

  if (form) {
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      const value = (emailInput.value || '').trim();
      const valid = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value);
      const dict = I18N[activeLang];
      if (!valid) {
        setStatus(dict['status-invalid'], 'err');
        emailInput.focus();
        return;
      }
      setStatus(dict['status-ok'], 'ok');
      emailInput.value = '';
      // Intentionally no backend yet — replace with a fetch() to your
      // launch-list endpoint once it exists.
    });
  }
})();
