/* Adscreen Belgium — landing interactivity
 *
 *   - NL / FR / EN language toggle, full coverage of every visible string.
 *     Default NL. Reads ?lang= query param > localStorage > navigator.language > NL.
 *   - Pre-launch form: client-side validation + friendly localised status.
 *     No backend wired — replace the handler with a real submit when the
 *     launch list endpoint exists.
 *   - Section reveal on scroll (subtle fade-in via IntersectionObserver).
 */

(function () {
  'use strict';

  // ── Translations ──────────────────────────────────────────────────
  const I18N = {
    nl: {
      // ribbon
      'ribbon-strong': 'Coming Soon',
      'ribbon-rest': '— Adscreen Belgium gaat live in Q3 2026. Reserveer je campagne nu.',
      'ribbon-cta': 'Vroege toegang →',
      // nav
      'nav-how': 'Hoe het werkt',
      'nav-numbers': 'In cijfers',
      'nav-coverage': 'Steden',
      'nav-faq': 'FAQ',
      'nav-cta': 'Hou me op de hoogte',
      // hero
      'hero-eyebrow': 'België · Q3 2026',
      'hero-title-1': 'Digitale taxi-reclame',
      'hero-title-2': 'die mensen écht zien.',
      'hero-lede':
        'Adscreen brengt premium interactieve schermen naar elke taxi en rideshare in België. Eén dashboard, duizenden ritten per dag, en spots die mensen actief aankijken in plaats van wegklikken.',
      'hero-cta-1': 'Reserveer je launch-slot',
      'hero-cta-2': 'Bekijk hoe het werkt',
      'trust-text': 'Powered by het team achter',
      // hero device
      'hero-ad-tag': 'Sponsored · 15s',
      'hero-ad-headline': 'Boek je vlucht naar Lissabon',
      'hero-ad-cta': 'Tap om QR te scannen →',
      'hero-ad-meta-route': 'Route · BXL-A12',
      'hero-ad-meta-impressions': 'Vandaag · 1.284 weergaven',
      'chip-1-strong': 'Live',
      'chip-1-rest': 'in 312 voertuigen',
      'chip-2-rest': 'CTR · deze week',
      'chip-3': 'NL · FR · EN, mee met de rit',
      // logos
      'logos-label': 'Pre-launch interesse van',
      // how
      'how-tag': 'Hoe het werkt',
      'how-title': 'Drie stappen tot je eerste live campagne.',
      'how-lede':
        'Geen wachttijd, geen drukwerk. Plan een spot, kies steden en doelgroep, en je campagne is binnen 24 uur live in honderden voertuigen.',
      'step-1-title': 'Plan',
      'step-1-body':
        'Kies steden, tijdsblokken en doelgroep. Upload je creatieve content of laat ons helpen bij de productie.',
      'step-2-title': 'Run',
      'step-2-body':
        'Spots draaien automatisch op het hele wagenpark. Onze software past zich aan per route, taal en tijdstip.',
      'step-3-title': 'Measure',
      'step-3-body':
        'Real-time rapportage: impressies, CTR, geografische heatmap, QR-scans. Volledig transparant.',
      // numbers
      'num-1': 'Schermen bij lancering',
      'num-2': 'Ritten per week',
      'num-3': 'Steden bij start',
      'num-4': 'Live monitoring',
      // why
      'why-tag': 'Waarom Adscreen',
      'why-title': 'Een advertentiekanaal dat niet weggeklikt kan worden.',
      'feat-1-title': 'Real-time controle',
      'feat-1-body':
        'Pauzeer, swap of update creatief vanaf één dashboard — wijzigingen zijn binnen seconden live op het hele wagenpark.',
      'feat-2-title': 'Geo- en tijd-targeting',
      'feat-2-body':
        'Andere boodschap in Brussel-Centrum dan op de E40. Spots schakelen automatisch per buurt, uur en taal.',
      'feat-3-title': 'Interactief',
      'feat-3-body':
        'Tappable QR-codes, mini-surveys en lead-formulieren — passagiers reageren in de rit zelf.',
      'feat-4-title': 'Volledige analytics',
      'feat-4-body':
        'Impressies, kijktijd, CTR, conversies — per spot, stad en uur. Exporteerbaar naar je bestaande stack.',
      'feat-5-title': 'Drietalig, by design',
      'feat-5-body':
        'Nederlands, Frans en Engels. Spots kunnen taalvoorkeur van de passagier respecteren of taalgemengd zijn.',
      'feat-6-title': 'Brand-safe & GDPR-first',
      'feat-6-body':
        'Geen camera-tracking, geen persoonlijke data — alleen geanonimiseerde route- en kijkstatistieken. Compliant by default.',
      // coverage
      'coverage-tag': 'Steden',
      'coverage-title': 'Start in 3 steden, daarna heel België.',
      'coverage-lede':
        'We beginnen waar het ritvolume het hoogst is en breiden uit naar elke provincie tegen midden 2027.',
      'city-1': 'Bruxelles · Lancering Q3 2026 · ~220 voertuigen pilot',
      'city-2': 'Antwerpen · Lancering Q3 2026 · ~180 voertuigen pilot',
      'city-3': 'Luik · Lancering Q4 2026 · ~100 voertuigen pilot',
      'city-4': 'Gent · 2027',
      'city-5': '2027',
      'city-6': 'Brugge · 2027',
      'city-7': 'Namen · 2027',
      'city-8': '2027',
      // pricing
      'pricing-tag': 'Prijzen · pre-launch',
      'pricing-title': 'Pakketten openen Q3 2026.',
      'pricing-lede':
        'Vroege partners krijgen toegang tot launch-pricing — gegarandeerd onder marktprijs voor de eerste 12 maanden, plus eerste keuze van premium routes.',
      'perk-1': 'Vaste introductieprijs tot eind 2026',
      'perk-2': 'Eerste keuze: routes, tijdsblokken, steden',
      'perk-3': 'Toegang tot creatieve studio voor je eerste spot',
      'perk-4': 'Maandelijks opzegbaar, geen jaarcontracten',
      'pricing-cta': 'Reserveer je plek',
      // notify
      'notify-tag': 'Launch-lijst',
      'notify-title': 'Wees als eerste live in 2026.',
      'notify-lede':
        'Laat je gegevens achter en we nemen persoonlijk contact op zodra je markt opent. Geen nieuwsbrief, geen spam — alleen launch-updates.',
      'contact-email-label': 'Direct contact',
      'form-name': 'Naam',
      'form-company': 'Bedrijf',
      'form-email': 'Werk-e-mail',
      'form-role': 'Ik ben…',
      'role-advertiser': 'Adverteerder / Bureau',
      'role-fleet': 'Taxi- of vlootbedrijf',
      'role-agency': 'Mediabureau',
      'role-other': 'Iets anders',
      'form-city': 'Stad van interesse',
      'city-option-other': 'Andere stad',
      'form-submit': 'Plaats me op de launch-lijst',
      'form-fine':
        'We slaan je gegevens veilig op en gebruiken ze alleen voor launch-communicatie. GDPR-compliant.',
      'status-invalid-email': 'Voer een geldig e-mailadres in.',
      'status-invalid-name': 'Vul je naam in.',
      'status-ok': 'Bedankt — we nemen binnenkort contact op.',
      // faq
      'faq-tag': 'FAQ',
      'faq-title': 'Veel gestelde vragen',
      'faq-1-q': 'Wanneer gaat Adscreen Belgium live?',
      'faq-1-a':
        'De officiële launch is gepland voor Q3 2026, beginnend in Brussel en Antwerpen. Pre-launch partners krijgen toegang in de pilotfase, vanaf juni 2026.',
      'faq-2-q': 'Hoe verschillen jullie van traditionele DOOH-borden?',
      'faq-2-a':
        'Onze schermen reizen mét de passagier — dezelfde rit door verschillende buurten, met spots die zich aanpassen aan locatie, tijdstip en taal. Je betaalt voor ritten met écht ogen, niet voor vaste billboards waar mensen langsrijden.',
      'faq-3-q': 'Welke creatieve formaten ondersteunen jullie?',
      'faq-3-a':
        '15- en 30-seconden video, statische beelden, interactieve QR-spots en korte surveys. Alle formaten worden geleverd in NL/FR/EN en kunnen automatisch wisselen per route.',
      'faq-4-q': 'Hoe zit het met privacy en GDPR?',
      'faq-4-a':
        'Geen gezichtsherkenning, geen persoonsgegevens. We meten alleen geanonimiseerde route-statistieken en QR-scans waarvoor de passagier zelf actie neemt. Volledig GDPR-conform.',
      'faq-5-q': 'Kan ik nu al een campagne reserveren?',
      'faq-5-a':
        'Ja — laat je gegevens achter via het launch-formulier hierboven en we plannen een gesprek in deze maand. De eerste 20 partners krijgen launch-pricing onder marktprijs voor het hele eerste jaar.',
      'faq-6-q': 'Rij je voor een taxibedrijf? Doe mee.',
      'faq-6-a':
        'We zoeken vloten van 10+ voertuigen in Brussel, Antwerpen en Luik om mee te starten. Chauffeurs ontvangen maandelijkse vergoeding plus dashboard om verdiensten te zien. Schrijf je in via het formulier.',
      // footer
      'footer-tagline': 'Digitale taxi-reclame voor België — binnenkort live.',
      'footer-product': 'Product',
      'footer-why': 'Waarom Adscreen',
      'footer-pricing': 'Prijzen',
      'footer-company': 'Bedrijf',
      'footer-az': 'Adscreen Azerbaijan',
      'footer-careers': 'Vacatures (binnenkort)',
      'footer-press': 'Pers',
      'footer-contact': 'Contact',
      'footer-addr': 'Brussel, België',
      'footer-copy': '© 2026 Adscreen Belgium · Een nieuw hoofdstuk van adscreen.az',
      'footer-privacy': 'Privacy',
      'footer-terms': 'Algemene voorwaarden',
      'footer-cookies': 'Cookies'
    },

    fr: {
      'ribbon-strong': 'Bientôt disponible',
      'ribbon-rest': '— Adscreen Belgium ouvre au Q3 2026. Réservez votre campagne maintenant.',
      'ribbon-cta': 'Accès anticipé →',
      'nav-how': 'Comment ça marche',
      'nav-numbers': 'En chiffres',
      'nav-coverage': 'Villes',
      'nav-faq': 'FAQ',
      'nav-cta': 'Tenez-moi au courant',
      'hero-eyebrow': 'Belgique · Q3 2026',
      'hero-title-1': 'La publicité taxi numérique',
      'hero-title-2': 'que les gens regardent vraiment.',
      'hero-lede':
        'Adscreen amène des écrans interactifs premium dans chaque taxi et VTC en Belgique. Un seul tableau de bord, des milliers de courses par jour, et des spots que les passagers regardent activement.',
      'hero-cta-1': 'Réservez votre créneau de lancement',
      'hero-cta-2': 'Voir comment ça fonctionne',
      'trust-text': 'Conçu par l’équipe derrière',
      'hero-ad-tag': 'Sponsorisé · 15s',
      'hero-ad-headline': 'Réservez votre vol vers Lisbonne',
      'hero-ad-cta': 'Touchez pour scanner le QR →',
      'hero-ad-meta-route': 'Route · BXL-A12',
      'hero-ad-meta-impressions': 'Aujourd’hui · 1 284 vues',
      'chip-1-strong': 'En direct',
      'chip-1-rest': 'dans 312 véhicules',
      'chip-2-rest': 'CTR · cette semaine',
      'chip-3': 'NL · FR · EN, qui suit la course',
      'logos-label': 'Intérêt pré-lancement de',
      'how-tag': 'Comment ça marche',
      'how-title': 'Trois étapes vers votre première campagne en direct.',
      'how-lede':
        'Pas d’attente, pas d’impression. Planifiez un spot, choisissez villes et audience — votre campagne est en direct dans des centaines de véhicules en 24h.',
      'step-1-title': 'Planifier',
      'step-1-body':
        'Choisissez villes, créneaux et audience. Téléchargez votre créatif ou laissez-nous vous aider à le produire.',
      'step-2-title': 'Diffuser',
      'step-2-body':
        'Les spots tournent automatiquement sur toute la flotte. Notre logiciel s’adapte à la route, à la langue et à l’heure.',
      'step-3-title': 'Mesurer',
      'step-3-body':
        'Rapports en temps réel : impressions, CTR, heatmap géographique, scans QR. Totalement transparent.',
      'num-1': 'Écrans au lancement',
      'num-2': 'Courses par semaine',
      'num-3': 'Villes au démarrage',
      'num-4': 'Monitoring en direct',
      'why-tag': 'Pourquoi Adscreen',
      'why-title': 'Un canal publicitaire qu’on ne peut pas ignorer.',
      'feat-1-title': 'Contrôle en temps réel',
      'feat-1-body':
        'Pause, swap ou mise à jour créative depuis un seul tableau de bord — les changements sont en direct sur toute la flotte en quelques secondes.',
      'feat-2-title': 'Ciblage géo et temporel',
      'feat-2-body':
        'Un autre message dans le centre de Bruxelles que sur la E40. Les spots changent automatiquement selon le quartier, l’heure et la langue.',
      'feat-3-title': 'Interactif',
      'feat-3-body':
        'QR-codes tactiles, mini-sondages, formulaires de lead — les passagers réagissent pendant la course.',
      'feat-4-title': 'Analytique complète',
      'feat-4-body':
        'Impressions, temps de vue, CTR, conversions — par spot, ville et heure. Exportable vers votre stack existant.',
      'feat-5-title': 'Trilingue par conception',
      'feat-5-body':
        'Néerlandais, français et anglais. Les spots peuvent respecter la préférence du passager ou être multilingues.',
      'feat-6-title': 'Brand-safe & RGPD-first',
      'feat-6-body':
        'Pas de reconnaissance faciale, pas de données personnelles — uniquement des statistiques de route et de vue anonymisées. Conforme par défaut.',
      'coverage-tag': 'Villes',
      'coverage-title': 'Démarrage dans 3 villes, puis toute la Belgique.',
      'coverage-lede':
        'Nous commençons là où le volume de courses est le plus élevé et étendons à chaque province d’ici mi-2027.',
      'city-1': 'Bruxelles · Lancement Q3 2026 · ~220 véhicules pilotes',
      'city-2': 'Anvers · Lancement Q3 2026 · ~180 véhicules pilotes',
      'city-3': 'Liège · Lancement Q4 2026 · ~100 véhicules pilotes',
      'city-4': 'Gand · 2027',
      'city-5': '2027',
      'city-6': 'Bruges · 2027',
      'city-7': 'Namur · 2027',
      'city-8': '2027',
      'pricing-tag': 'Tarifs · pré-lancement',
      'pricing-title': 'Les forfaits ouvrent au Q3 2026.',
      'pricing-lede':
        'Les partenaires précoces accèdent au tarif de lancement — garanti sous le prix du marché pour les 12 premiers mois, plus premier choix des routes premium.',
      'perk-1': 'Tarif d’introduction fixe jusque fin 2026',
      'perk-2': 'Premier choix : routes, créneaux, villes',
      'perk-3': 'Accès au studio créatif pour votre premier spot',
      'perk-4': 'Résiliable au mois, sans contrat annuel',
      'pricing-cta': 'Réservez votre place',
      'notify-tag': 'Liste de lancement',
      'notify-title': 'Soyez en direct dès 2026.',
      'notify-lede':
        'Laissez vos coordonnées et nous vous contactons dès l’ouverture de votre marché. Pas de newsletter, pas de spam — uniquement des mises à jour de lancement.',
      'contact-email-label': 'Contact direct',
      'form-name': 'Nom',
      'form-company': 'Société',
      'form-email': 'E-mail professionnel',
      'form-role': 'Je suis…',
      'role-advertiser': 'Annonceur / Marque',
      'role-fleet': 'Taxi ou société de flotte',
      'role-agency': 'Agence média',
      'role-other': 'Autre',
      'form-city': 'Ville d’intérêt',
      'city-option-other': 'Autre ville',
      'form-submit': 'Inscrivez-moi à la liste de lancement',
      'form-fine':
        'Vos données sont stockées en toute sécurité et utilisées uniquement pour les communications de lancement. Conforme RGPD.',
      'status-invalid-email': 'Veuillez saisir une adresse e-mail valide.',
      'status-invalid-name': 'Veuillez saisir votre nom.',
      'status-ok': 'Merci — nous vous contacterons bientôt.',
      'faq-tag': 'FAQ',
      'faq-title': 'Questions fréquentes',
      'faq-1-q': 'Quand Adscreen Belgium sera-t-il disponible ?',
      'faq-1-a':
        'Le lancement officiel est prévu au Q3 2026, à commencer par Bruxelles et Anvers. Les partenaires pré-lancement accèdent à la phase pilote dès juin 2026.',
      'faq-2-q': 'En quoi êtes-vous différents du DOOH traditionnel ?',
      'faq-2-a':
        'Nos écrans voyagent avec le passager — la même course traverse plusieurs quartiers, avec des spots qui s’adaptent au lieu, à l’heure et à la langue. Vous payez pour des courses avec de vrais regards, pas des panneaux devant lesquels on passe.',
      'faq-3-q': 'Quels formats créatifs prenez-vous en charge ?',
      'faq-3-a':
        'Vidéo 15s et 30s, images statiques, spots QR interactifs, et courts sondages. Tous les formats sont livrés en NL/FR/EN et peuvent changer automatiquement selon la route.',
      'faq-4-q': 'Et la confidentialité / RGPD ?',
      'faq-4-a':
        'Pas de reconnaissance faciale, pas de données personnelles. Nous mesurons uniquement des statistiques de route anonymisées et des scans QR initiés par le passager. Totalement conforme RGPD.',
      'faq-5-q': 'Puis-je réserver une campagne dès maintenant ?',
      'faq-5-a':
        'Oui — laissez vos coordonnées via le formulaire ci-dessus et nous planifions un appel ce mois-ci. Les 20 premiers partenaires obtiennent le tarif de lancement sous le marché pour toute la première année.',
      'faq-6-q': 'Vous gérez une flotte de taxis ? Rejoignez-nous.',
      'faq-6-a':
        'Nous recherchons des flottes de 10+ véhicules à Bruxelles, Anvers et Liège pour démarrer. Les chauffeurs reçoivent une rémunération mensuelle plus un tableau de bord pour suivre leurs gains. Inscrivez-vous via le formulaire.',
      'footer-tagline': 'Publicité taxi numérique pour la Belgique — bientôt en direct.',
      'footer-product': 'Produit',
      'footer-why': 'Pourquoi Adscreen',
      'footer-pricing': 'Tarifs',
      'footer-company': 'Société',
      'footer-az': 'Adscreen Azerbaïdjan',
      'footer-careers': 'Carrières (bientôt)',
      'footer-press': 'Presse',
      'footer-contact': 'Contact',
      'footer-addr': 'Bruxelles, Belgique',
      'footer-copy': '© 2026 Adscreen Belgium · Un nouveau chapitre d’adscreen.az',
      'footer-privacy': 'Confidentialité',
      'footer-terms': 'Conditions',
      'footer-cookies': 'Cookies'
    },

    en: {
      'ribbon-strong': 'Coming Soon',
      'ribbon-rest': '— Adscreen Belgium launches Q3 2026. Reserve your campaign now.',
      'ribbon-cta': 'Get early access →',
      'nav-how': 'How it works',
      'nav-numbers': 'By the numbers',
      'nav-coverage': 'Cities',
      'nav-faq': 'FAQ',
      'nav-cta': 'Notify me',
      'hero-eyebrow': 'Belgium · Q3 2026',
      'hero-title-1': 'Taxi screen advertising',
      'hero-title-2': 'that people actually watch.',
      'hero-lede':
        'Adscreen brings premium interactive screens to every taxi and rideshare in Belgium. One dashboard, thousands of rides a day, and spots that riders lean into instead of swipe away.',
      'hero-cta-1': 'Reserve your launch slot',
      'hero-cta-2': 'See how it works',
      'trust-text': 'Built by the team behind',
      'hero-ad-tag': 'Sponsored · 15s',
      'hero-ad-headline': 'Book your flight to Lisbon',
      'hero-ad-cta': 'Tap to scan QR →',
      'hero-ad-meta-route': 'Route · BXL-A12',
      'hero-ad-meta-impressions': 'Today · 1,284 views',
      'chip-1-strong': 'Live',
      'chip-1-rest': 'in 312 vehicles',
      'chip-2-rest': 'CTR · this week',
      'chip-3': 'NL · FR · EN, along for the ride',
      'logos-label': 'Pre-launch interest from',
      'how-tag': 'How it works',
      'how-title': 'Three steps to your first live campaign.',
      'how-lede':
        'No waiting, no printing. Plan a spot, pick cities and audience, and your campaign is live in hundreds of vehicles within 24 hours.',
      'step-1-title': 'Plan',
      'step-1-body':
        'Pick cities, time slots and audience. Upload your creative or let us help produce it.',
      'step-2-title': 'Run',
      'step-2-body':
        'Spots play automatically across the fleet. Our software adapts to route, language and time of day.',
      'step-3-title': 'Measure',
      'step-3-body':
        'Real-time reporting: impressions, CTR, geographic heatmap, QR scans. Fully transparent.',
      'num-1': 'Screens at launch',
      'num-2': 'Rides per week',
      'num-3': 'Cities at start',
      'num-4': 'Live monitoring',
      'why-tag': 'Why Adscreen',
      'why-title': 'An ad channel you can’t scroll past.',
      'feat-1-title': 'Real-time control',
      'feat-1-body':
        'Pause, swap or update creative from one dashboard — changes go live across the fleet in seconds.',
      'feat-2-title': 'Geo and time targeting',
      'feat-2-body':
        'Different message in Brussels-Centre than on the E40. Spots switch automatically by neighborhood, hour and language.',
      'feat-3-title': 'Interactive',
      'feat-3-body':
        'Tappable QR codes, mini-surveys, lead forms — riders react inside the ride itself.',
      'feat-4-title': 'Full analytics',
      'feat-4-body':
        'Impressions, view time, CTR, conversions — per spot, city and hour. Exportable to your existing stack.',
      'feat-5-title': 'Trilingual by design',
      'feat-5-body':
        'Dutch, French and English. Spots can respect rider language preference or stay bilingual.',
      'feat-6-title': 'Brand-safe & GDPR-first',
      'feat-6-body':
        'No face tracking, no personal data — only anonymised route and view stats. Compliant by default.',
      'coverage-tag': 'Cities',
      'coverage-title': 'Start in 3 cities, then all of Belgium.',
      'coverage-lede':
        'We start where ride volume is highest and roll out to every province by mid-2027.',
      'city-1': 'Bruxelles · Launching Q3 2026 · ~220 pilot vehicles',
      'city-2': 'Antwerpen · Launching Q3 2026 · ~180 pilot vehicles',
      'city-3': 'Luik · Launching Q4 2026 · ~100 pilot vehicles',
      'city-4': 'Ghent · 2027',
      'city-5': '2027',
      'city-6': 'Bruges · 2027',
      'city-7': 'Namur · 2027',
      'city-8': '2027',
      'pricing-tag': 'Pricing · pre-launch',
      'pricing-title': 'Packages open Q3 2026.',
      'pricing-lede':
        'Early partners get launch pricing — guaranteed below market for the first 12 months, plus first pick of premium routes.',
      'perk-1': 'Fixed intro pricing through end of 2026',
      'perk-2': 'First choice: routes, time slots, cities',
      'perk-3': 'Access to creative studio for your first spot',
      'perk-4': 'Cancel any month — no annual contracts',
      'pricing-cta': 'Reserve your slot',
      'notify-tag': 'Pre-launch list',
      'notify-title': 'Be live on day one in 2026.',
      'notify-lede':
        'Leave your details and we’ll reach out personally the moment your market opens. No newsletter, no spam — just launch updates.',
      'contact-email-label': 'Direct contact',
      'form-name': 'Name',
      'form-company': 'Company',
      'form-email': 'Work email',
      'form-role': 'I am…',
      'role-advertiser': 'Advertiser / Brand',
      'role-fleet': 'Taxi or fleet company',
      'role-agency': 'Media agency',
      'role-other': 'Something else',
      'form-city': 'City of interest',
      'city-option-other': 'Other city',
      'form-submit': 'Put me on the launch list',
      'form-fine':
        'We store your details securely and use them only for launch communication. GDPR-compliant.',
      'status-invalid-email': 'Please enter a valid email address.',
      'status-invalid-name': 'Please enter your name.',
      'status-ok': 'Thanks — we’ll be in touch shortly.',
      'faq-tag': 'FAQ',
      'faq-title': 'Frequently asked questions',
      'faq-1-q': 'When does Adscreen Belgium go live?',
      'faq-1-a':
        'Official launch is planned for Q3 2026, starting in Brussels and Antwerp. Pre-launch partners get pilot access from June 2026.',
      'faq-2-q': 'How are you different from traditional DOOH billboards?',
      'faq-2-a':
        'Our screens travel with the passenger — the same ride passes through multiple neighborhoods, with spots that adapt to location, time and language. You pay for rides with real eyeballs, not for fixed billboards people drive past.',
      'faq-3-q': 'What creative formats do you support?',
      'faq-3-a':
        '15- and 30-second video, static images, interactive QR spots, and short surveys. All formats ship in NL/FR/EN and can switch automatically by route.',
      'faq-4-q': 'What about privacy and GDPR?',
      'faq-4-a':
        'No face recognition, no personal data. We only measure anonymised route stats and QR scans initiated by the passenger. Fully GDPR-compliant.',
      'faq-5-q': 'Can I reserve a campaign now?',
      'faq-5-a':
        'Yes — leave your details via the launch form above and we’ll schedule a call this month. The first 20 partners get below-market launch pricing for the entire first year.',
      'faq-6-q': 'Drive for a taxi company? Join us.',
      'faq-6-a':
        'We’re looking for fleets of 10+ vehicles in Brussels, Antwerp and Liège to start. Drivers receive monthly compensation plus a dashboard to track earnings. Sign up via the form.',
      'footer-tagline': 'Digital taxi advertising for Belgium — coming soon.',
      'footer-product': 'Product',
      'footer-why': 'Why Adscreen',
      'footer-pricing': 'Pricing',
      'footer-company': 'Company',
      'footer-az': 'Adscreen Azerbaijan',
      'footer-careers': 'Careers (soon)',
      'footer-press': 'Press',
      'footer-contact': 'Contact',
      'footer-addr': 'Brussels, Belgium',
      'footer-copy': '© 2026 Adscreen Belgium · A new chapter of adscreen.az',
      'footer-privacy': 'Privacy',
      'footer-terms': 'Terms',
      'footer-cookies': 'Cookies'
    }
  };

  // ── Language switching ────────────────────────────────────────────
  const langButtons = document.querySelectorAll('.lang-btn');
  const i18nNodes = document.querySelectorAll('[data-i18n]');
  let activeLang = 'nl';

  function applyLanguage(lang) {
    const dict = I18N[lang];
    if (!dict) return;
    activeLang = lang;
    document.documentElement.lang = lang === 'en' ? 'en' : lang + '-BE';

    i18nNodes.forEach((node) => {
      const key = node.getAttribute('data-i18n');
      const text = dict[key];
      if (text === undefined) return;
      // <option> uses textContent; everything else also uses textContent.
      node.textContent = text;
    });

    langButtons.forEach((btn) => {
      const active = btn.dataset.lang === lang;
      btn.classList.toggle('is-active', active);
      btn.setAttribute('aria-selected', String(active));
    });

    try {
      localStorage.setItem('adscreen-be-lang', lang);
    } catch (_) {}
  }

  langButtons.forEach((btn) => {
    btn.addEventListener('click', () => applyLanguage(btn.dataset.lang));
  });

  // Decide initial language
  function pickInitialLang() {
    const params = new URLSearchParams(window.location.search);
    const fromQuery = params.get('lang');
    if (fromQuery && I18N[fromQuery]) return fromQuery;
    try {
      const saved = localStorage.getItem('adscreen-be-lang');
      if (saved && I18N[saved]) return saved;
    } catch (_) {}
    const nav = (navigator.language || '').toLowerCase();
    if (nav.startsWith('fr')) return 'fr';
    if (nav.startsWith('en')) return 'en';
    return 'nl';
  }
  applyLanguage(pickInitialLang());

  // ── Pre-launch form ───────────────────────────────────────────────
  const form = document.getElementById('notify-form');
  const statusEl = document.getElementById('form-status');
  const nameEl = document.getElementById('name');
  const emailEl = document.getElementById('email');

  function setStatus(text, kind) {
    if (!statusEl) return;
    statusEl.textContent = text;
    statusEl.classList.remove('ok', 'err');
    if (kind) statusEl.classList.add(kind);
  }

  if (form) {
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      const dict = I18N[activeLang];
      const name = (nameEl.value || '').trim();
      const email = (emailEl.value || '').trim();
      if (!name) {
        setStatus(dict['status-invalid-name'], 'err');
        nameEl.focus();
        return;
      }
      const validEmail = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email);
      if (!validEmail) {
        setStatus(dict['status-invalid-email'], 'err');
        emailEl.focus();
        return;
      }
      setStatus(dict['status-ok'], 'ok');
      form.reset();
      // Backend wiring placeholder — replace with fetch('/api/launch-list', …)
      // once the endpoint exists. Captures intent client-side only for now.
    });
  }

  // ── Subtle scroll reveal ─────────────────────────────────────────
  if ('IntersectionObserver' in window) {
    const reveal = (el) => {
      el.style.opacity = '0';
      el.style.transform = 'translateY(12px)';
      el.style.transition = 'opacity 500ms ease, transform 500ms ease';
    };
    const targets = document.querySelectorAll(
      '.section, .numbers, .logos, .pricing-card'
    );
    targets.forEach(reveal);
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.style.opacity = '1';
            entry.target.style.transform = 'translateY(0)';
            io.unobserve(entry.target);
          }
        });
      },
      { rootMargin: '0px 0px -10% 0px', threshold: 0.05 }
    );
    targets.forEach((t) => io.observe(t));
  }
})();
