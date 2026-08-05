// Download and star counts as pills at the end of the nav, on every page.
// stats.json is refreshed nightly by .github/workflows/stats.yml, so this is a
// same-origin static file rather than a GitHub API call per visitor.
const REPO = "https://github.com/saeedkolivand/claude-usage-mac";

fetch("/stats.json")
  .then((r) => r.json())
  .then(({ downloads, stars }) => {
    const nav = document.querySelector(".nav__inner");
    if (!nav) return;
    const pill = (href, glyph, count, label) => {
      if (!count) return;
      const a = document.createElement("a");
      a.className = "nav__stat";
      a.href = href;
      a.textContent = `${glyph} ${count.toLocaleString()}`;
      a.setAttribute("aria-label", `${count.toLocaleString()} ${label}`);
      nav.append(a);
    };
    pill(`${REPO}/stargazers`, "★", stars, "stars on GitHub");
    pill(`${REPO}/releases`, "↓", downloads, "downloads");
  })
  .catch(() => {});
