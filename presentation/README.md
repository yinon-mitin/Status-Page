# Status-Page presentation

Static 16:9 HTML deck for the DevOps final-project jury presentation.

## Run locally

From the repository root:

```bash
python3 -m http.server 8000 --directory presentation
```

Open <http://localhost:8000/>.

The deck can also be opened directly from `presentation/index.html`, but a local HTTP server gives the closest behavior to GitHub Pages.

## Present

- **Right Arrow** or **Space** — next slide
- **Left Arrow** — previous slide
- **Home** / **End** — first / last slide
- **N** — toggle presenter notes
- **F** — toggle browser fullscreen
- **P** — print or save as PDF
- **?** — keyboard shortcut help
- Swipe horizontally on a touch device
- Click the left or right edge of a slide, or use the navigation buttons

The current slide is stored locally and reflected in the URL fragment, so reloading preserves the position. Presenter notes are hidden from the audience view and appear in a separate overlay.

## Deck structure

- 14 main slides
- 5 appendix slides
- 19 slides total

The normal talk ends on **What did I learn about DevOps methodology?** Appendix slides follow for jury questions.

## Print / PDF

Press **P** or use the browser print dialog. Select landscape orientation, disable browser headers/footers, and enable background graphics. The stylesheet emits one 16:9 slide per page.

## GitHub Pages

`.github/workflows/pages.yml` uploads only the `presentation/` directory and deploys it with the official GitHub Pages actions. It does not call AWS, Terraform, or any production lifecycle script.

Expected URL:

<https://yinon-mitin.github.io/Status-Page/>

Repository status: Pages is configured to use **GitHub Actions**, so no manual setting is required for this repository.

For a fork where Pages is still disabled, perform this one-time action:

1. Open **Repository Settings → Pages**.
2. Under **Build and deployment → Source**, select **GitHub Actions**.
3. Re-run **Deploy presentation to GitHub Pages** from the Actions tab.

## Content sources

Project-specific claims are based on repository source, especially:

- `README.md`
- `UPSTREAM.md`
- `docs/ARCHITECTURE.md`
- `docs/PRODUCTION_LIFECYCLE.md`
- `docs/DELIVERY_EVIDENCE.md`
- `docs/TECHNOLOGY_INDEX.md`
- `terraform/`
- `.github/workflows/`
- `scripts/`
- `tests/`

The evidence slide describes the documented historical AWS rehearsal. It does not imply that the production environment is still running.
