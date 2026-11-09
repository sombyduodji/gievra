// Kotisivun karttahaku: hakee kunnan tai alueen nimellä site/kartat.json:sta ja näyttää latauslinkit.
// Tiedot tulevat tools/site_maps.py:stä. Kieli sivun <html lang> -määreestä (fi tai en).
(function () {
  var box = document.getElementById('maphaku');
  if (!box) return;
  var en = document.documentElement.lang === 'en';
  var L = en ? {
    all: 'All countries', loading: 'Loading the map list…', fail: 'The map list could not be loaded.',
    none: 'No maps found. Try another spelling or the name of a nearby municipality or region.',
    more: 'Showing {0} of {1}. Type more of the name to narrow the list.',
    hint: 'Type at least 2 letters, e.g. Inari, Tromsø, Edinburgh or Málaga.',
    count: '{0} maps in {1} countries · OpenStreetMap data {2}',
    ov: 'Overview map of {0}', ovNote: 'Download the overview map once per country: it is the zoomed-out background for the area maps.',
    dl: 'Download', elev: 'Elevation data', kb: 'kB', mb: 'MB', gb: 'GB'
  } : {
    all: 'Kaikki maat', loading: 'Ladataan karttaluetteloa…', fail: 'Karttaluetteloa ei saatu ladattua.',
    none: 'Karttoja ei löytynyt. Kokeile toista kirjoitusasua tai lähikunnan tai alueen nimeä.',
    more: 'Näytetään {0}/{1}. Kirjoita nimeä pidemmälle, niin lista lyhenee.',
    hint: 'Kirjoita vähintään 2 kirjainta, esim. Inari, Tromsø, Edinburgh tai Málaga.',
    count: '{0} karttaa {1} maassa · OpenStreetMap-aineisto {2}',
    ov: 'Yleiskartta: {0}', ovNote: 'Lataa yleiskartta kerran maata kohden: se on loitonnetun näkymän tausta aluekartoille.',
    dl: 'Lataa', elev: 'Korkeustiedot', kb: 'kt', mb: 'Mt', gb: 'Gt'
  };
  var MAX = 40;
  var q = box.querySelector('input'), sel = box.querySelector('select'), out = box.querySelector('.tulokset'),
      info = box.querySelector('.tila');
  var data = null, rows = [];

  function fmt(s) { var a = arguments; return s.replace(/\{(\d)\}/g, function (_, i) { return a[+i + 1]; }); }
  function fold(s) { return s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[øö]/g, 'o').replace(/[æä]/g, 'a').replace(/å/g, 'a').replace(/ð/g, 'd').replace(/þ/g, 'th')
    .replace(/ŋ/g, 'n').replace(/đ/g, 'd').replace(/ŧ/g, 't').replace(/š/g, 's').replace(/ž/g, 'z').replace(/č/g, 'c'); }
  function size(b) {
    var m = b / 1048576;
    if (m < 1) return Math.max(1, Math.round(b / 1024)) + ' ' + L.kb;
    if (m >= 1000) return (m / 1024).toFixed(1).replace('.', en ? '.' : ',') + ' ' + L.gb;
    return (m < 10 ? m.toFixed(1).replace('.', en ? '.' : ',') : Math.round(m)) + ' ' + L.mb;
  }
  function cname(c) { return en ? c.names.en : c.names.fi; }
  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text) e.textContent = text; return e; }
  function link(href, text) { var a = el('a', 'btn primary', text); a.href = href; a.rel = 'nofollow'; return a; }

  function render() {
    out.textContent = '';
    if (!data) return;
    var term = fold(q.value.trim()), cc = sel.value;
    if (term.length < 2 && !cc) { info.textContent = L.hint; return; }
    var hits = rows.filter(function (r) {
      return (!cc || r.c.id === cc) && (term.length < 2 || r.key.indexOf(term) >= 0);
    });
    // Nimen alusta osuvat ensin, sitten nimen sisältä tai muista nimistä, viimeisenä alueen tai maan nimellä.
    function rank(r) { return r.name.indexOf(term) === 0 ? 0 : r.names.indexOf(term) >= 0 ? 1 : 2; }
    hits.sort(function (a, b) { return rank(a) - rank(b) || a.p[0].localeCompare(b.p[0]); });
    info.textContent = !hits.length ? L.none : hits.length > MAX ? fmt(L.more, MAX, hits.length) : '';
    var countries = [];
    hits.slice(0, MAX).forEach(function (r) {
      if (countries.indexOf(r.c) < 0) countries.push(r.c);
      var li = el('li'), t = el('div');
      t.appendChild(el('b', null, r.p[0]));
      if (r.p[1]) t.appendChild(el('span', 'alt', ' (' + r.p[1] + ')'));
      t.appendChild(el('div', 'sub', [r.p[2], cname(r.c)].filter(Boolean).join(' · ')));
      li.appendChild(t);
      li.appendChild(link(r.c.base + r.p[4], L.dl + ' · ' + size(r.p[3])));
      if (r.p[5]) {  // korkeustiedot (Suomi: Maanmittauslaitos), oma tiedostonsa
        var e = link(r.c.base + r.p[5], L.elev + ' · ' + size(r.p[6]));
        e.className = 'btn secondary';
        li.appendChild(e);
      }
      out.appendChild(li);
    });
    if (countries.length) {
      var note = el('li', 'yleis');
      var t = el('div'); t.appendChild(el('div', 'sub', L.ovNote)); note.appendChild(t);
      var links = el('div', 'linkit');
      countries.forEach(function (c) {
        var a = link(c.base + c.overview[0], fmt(L.ov, cname(c)) + ' · ' + size(c.overview[1]));
        a.className = 'btn secondary'; links.appendChild(a);
      });
      note.appendChild(links);
      out.appendChild(note);
    }
  }

  info.textContent = L.loading;
  fetch(box.dataset.src).then(function (r) { if (!r.ok) throw r.status; return r.json(); }).then(function (d) {
    data = d;
    d.countries.slice().sort(function (a, b) { return cname(a).localeCompare(cname(b)); }).forEach(function (c) {
      var o = el('option', null, cname(c)); o.value = c.id; sel.appendChild(o);
    });
    d.countries.forEach(function (c) {
      c.packs.forEach(function (p) {
        rows.push({ c: c, p: p, name: fold(p[0]), names: fold(p[0] + ' ' + p[1]), key: fold([p[0], p[1], p[2], c.names.fi, c.names.en, c.names.local].join(' ')) });
      });
    });
    var n = 0; d.countries.forEach(function (c) { n += c.packs.length; });
    box.querySelector('.maara').textContent = fmt(L.count, n.toLocaleString(en ? 'en' : 'fi'), d.countries.length, d.osmDate);
    render();
  }).catch(function () { info.textContent = L.fail; });
  q.addEventListener('input', render);
  sel.addEventListener('change', render);
})();
