// The page's own logic: a theme, a scrollbar that fades in, and two demos that call this library
// compiled to JavaScript. Anything the library can answer is answered by the library; this file only
// moves strings and numbers into the document.

const root = document.documentElement;

const markAtTop = () => root.classList.toggle("at-top", scrollY === 0);
addEventListener("scroll", markAtTop, { passive: true });
markAtTop();

const asked = new URLSearchParams(location.search).get("theme");
const stored = localStorage.getItem("moonrag-theme");
if (asked === "light" || asked === "dark") root.dataset.theme = asked;
else if (stored === "light" || stored === "dark") root.dataset.theme = stored;
else root.dataset.theme = matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";

// Follow the system while the reader has not chosen a theme of their own; the choice is one value for
// every page on the site, so a page opened later inherits it.
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (event) => {
  if (!localStorage.getItem("moonrag-theme")) root.dataset.theme = event.matches ? "dark" : "light";
});

const toggle = document.querySelector("[data-theme-toggle]");
if (toggle) {
  toggle.addEventListener("click", () => {
    const next = root.dataset.theme === "dark" ? "light" : "dark";
    root.dataset.theme = next;
    localStorage.setItem("moonrag-theme", next);
  });
}

const engine = await import("./engine/moonrag.js").catch(() => null);

function text(result) {
  if (typeof result === "string") return result;
  if (result && typeof result === "object" && "_0" in result) return result._0;
  throw new Error("the engine refused this input");
}

function call(name, ...args) {
  if (!engine) throw new Error("the engine is not built here");
  return JSON.parse(text(engine[name](...args)));
}

function setStatus(node, message) {
  if (node) node.textContent = message;
}

function el(tag, className, content) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (content !== undefined) node.textContent = content;
  return node;
}

// ---------- the retrieval rail -------------------------------------------------------------

function railChunks(chunks) {
  const box = document.querySelector("[data-rail-chunks]");
  if (!box) return;
  box.replaceChildren();
  chunks.slice(0, 7).forEach((chunk, i) => {
    const row = el("div", "rail-row");
    row.append(el("span", "n", String(i + 1)));
    row.append(el("span", "t", chunk.t.replace(/\s+/g, " ").slice(0, 34)));
    row.append(el("span", "v", String(chunk.n)));
    box.append(row);
  });
  if (chunks.length > 7) {
    box.append(el("div", "rail-row", `+${chunks.length - 7} more`));
  }
}

function railHits(hits) {
  const box = document.querySelector("[data-rail-hits]");
  if (!box) return;
  box.replaceChildren();
  hits.forEach((hit, i) => {
    const row = el("div", "rail-row");
    // Rank, not the passage's place in the corpus: the rail and the table should be read together.
    row.append(el("span", "n", String(i + 1)));
    row.append(el("span", "t", hit.t.replace(/\s+/g, " ").slice(0, 34)));
    row.append(el("span", "v", hit.score.toFixed(3)));
    box.append(row);
  });
}

// ---------- the splitter demo --------------------------------------------------------------

document.querySelectorAll("[data-splitter]").forEach((figure) => {
  const area = figure.querySelector("[data-text]");
  const strip = figure.querySelector("[data-strip]");
  const size = figure.querySelector("[data-size]");
  const overlap = figure.querySelector("[data-overlap]");
  const sizeOut = figure.querySelector("[data-size-out]");
  const overlapOut = figure.querySelector("[data-overlap-out]");
  const status = figure.querySelector("[data-status]");
  let mode = "markdown";

  figure.querySelectorAll("[data-mode]").forEach((button) => {
    button.addEventListener("click", () => {
      mode = button.dataset.mode;
      figure.querySelectorAll("[data-mode]").forEach((other) => {
        other.setAttribute("aria-pressed", String(other === button));
      });
      draw();
    });
  });

  function draw() {
    const sizeValue = Number(size.value);
    const overlapValue = Math.min(Number(overlap.value), sizeValue - 1);
    overlap.max = String(Math.max(0, sizeValue - 1));
    if (Number(overlap.value) !== overlapValue) overlap.value = String(overlapValue);
    if (sizeOut) sizeOut.textContent = String(sizeValue);
    if (overlapOut) overlapOut.textContent = String(overlapValue);

    let data;
    try {
      data = call("browser_split", area.value, mode, sizeValue, overlapValue);
    } catch (error) {
      setStatus(status, error.message);
      strip.replaceChildren();
      return;
    }

    strip.replaceChildren();
    let widest = 0;
    let whole = 0;
    data.chunks.forEach((chunk, i) => {
      widest = Math.max(widest, chunk.n);
      if (chunk.code) whole += 1;
      const row = el("div", "chunk");
      row.append(el("div", "chunk-no", String(i + 1)));
      const body = el("div");
      const textNode = el("p", "chunk-text", chunk.t);
      if (chunk.code) textNode.append(el("span", "chunk-tag", "uncut"));
      body.append(textNode);
      if (chunk.path) body.append(el("div", "chunk-path", chunk.path));
      row.append(body);
      strip.append(row);
    });

    const parts = [
      `${data.count} chunk${data.count === 1 ? "" : "s"}`,
      `widest ${widest}`,
      whole ? `${whole} code kept whole` : "no code block",
    ];
    setStatus(status, parts.join(" · "));
    railChunks(data.chunks);
  }

  area.addEventListener("input", draw);
  size.addEventListener("input", draw);
  overlap.addEventListener("input", draw);
  draw();
});

// ---------- the retriever demo -------------------------------------------------------------

document.querySelectorAll("[data-retriever]").forEach((figure) => {
  const hitsBody = figure.querySelector("[data-hits]");
  const queries = figure.querySelector("[data-queries]");
  const lambda = figure.querySelector("[data-lambda]");
  const lambdaOut = figure.querySelector("[data-lambda-out]");
  const k = figure.querySelector("[data-k]");
  const kOut = figure.querySelector("[data-k-out]");
  const status = figure.querySelector("[data-status]");
  const lambdaRow = figure.querySelector("[data-lambda-row]");
  let order = "mmr";
  let query = 0;
  let corpus = null;

  try {
    corpus = call("browser_corpus");
  } catch (error) {
    setStatus(status, error.message);
  }

  if (corpus && queries) {
    corpus.queries.forEach((entry, i) => {
      const button = el("button", "", entry.label);
      button.type = "button";
      button.dataset.query = String(i);
      button.setAttribute("aria-pressed", String(i === 0));
      button.addEventListener("click", () => {
        query = i;
        queries.querySelectorAll("button").forEach((other) => {
          other.setAttribute("aria-pressed", String(other === button));
        });
        draw();
      });
      queries.append(button);
    });
  }

  figure.querySelectorAll("[data-order]").forEach((button) => {
    button.addEventListener("click", () => {
      order = button.dataset.order;
      figure.querySelectorAll("[data-order]").forEach((other) => {
        other.setAttribute("aria-pressed", String(other === button));
      });
      if (lambdaRow) lambdaRow.hidden = order !== "mmr";
      draw();
    });
  });

  function draw() {
    if (lambdaOut) lambdaOut.textContent = Number(lambda.value).toFixed(2);
    if (kOut) kOut.textContent = k.value;

    let data;
    try {
      data =
        order === "mmr"
          ? call("browser_mmr", query, Number(lambda.value), Number(k.value))
          : call("browser_rank", query, Number(k.value));
    } catch (error) {
      setStatus(status, error.message);
      return;
    }

    hitsBody.replaceChildren();
    data.hits.forEach((hit, i) => {
      const tr = el("tr");
      if (i === 0) tr.className = "top";
      tr.append(el("td", "rank-no", String(i + 1)));
      const cell = el("td");
      cell.append(document.createTextNode(hit.t));
      if (hit.src) cell.append(el("span", "source", hit.src));
      tr.append(cell);
      tr.append(el("td", "score", hit.score.toFixed(3)));
      hitsBody.append(tr);
    });

    const spread = data.hits.length
      ? (data.hits[0].score - data.hits[data.hits.length - 1].score).toFixed(3)
      : "0.000";
    setStatus(
      status,
      order === "mmr"
        ? `${data.hits.length} picked · lambda ${Number(lambda.value).toFixed(2)} · spread ${spread}`
        : `${data.hits.length} hits · spread ${spread}`,
    );
    railHits(data.hits);
  }

  if (lambdaRow && order !== "mmr") lambdaRow.hidden = true;
  if (lambda) lambda.addEventListener("input", draw);
  if (k) k.addEventListener("input", draw);
  draw();
});

// ---------- the rail follows the reader ----------------------------------------------------

const sections = [...document.querySelectorAll("[data-label], section[id$='-top']")];
const marker = document.querySelector("[data-rail-section]");
const toc = document.querySelectorAll(".toc a[href^='#']");

// Which section is being read: the last one whose top has gone under the header. Picking the
// topmost section that merely intersects would name the chapter the reader has just left, because
// its tail still shows at the top of the screen.
function reading() {
  // At the end of the page the last section cannot reach the header, so it is the one being read.
  if (innerHeight + scrollY >= document.documentElement.scrollHeight - 2) {
    return sections[sections.length - 1];
  }
  let current = sections[0];
  for (const section of sections) {
    if (section.getBoundingClientRect().top <= 80) current = section;
  }
  return current;
}

if (sections.length && marker && "IntersectionObserver" in window) {
  let queued = 0;
  const update = () => {
    queued = 0;
    const section = reading();
    // The home page labels its sections; the API reference names them in the heading.
    const label = section.dataset.label || (section.querySelector("h2")?.textContent || "").trim();
    if (label) marker.textContent = label;
    // A contents list marks where the reader is, if its links point at these sections.
    const at = section.id ? "#" + section.id : "";
    toc.forEach((link) => {
      if (at && link.getAttribute("href") === at) link.setAttribute("aria-current", "true");
      else link.removeAttribute("aria-current");
    });
  };
  const observer = new IntersectionObserver(
    () => {
      if (!queued) queued = requestAnimationFrame(update);
    },
    { rootMargin: "-72px 0px -50% 0px", threshold: [0, 1] },
  );
  sections.forEach((section) => observer.observe(section));
  update();
}

// ---------- copy the install line -----------------------------------------------------------

document.querySelectorAll("[data-copy]").forEach((button) => {
  button.addEventListener("click", async () => {
    const value = button.dataset.copy;
    try {
      await navigator.clipboard.writeText(value);
      button.textContent = "copied";
      setTimeout(() => {
        button.textContent = "copy";
      }, 1200);
    } catch {
      button.textContent = value;
    }
  });
});
