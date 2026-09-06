# Status-Page presentation

Static 16:9 HTML deck for the DevOps final-project jury presentation. HTML, CSS,
vanilla JavaScript and local assets only; no runtime dependencies or build step.

## Run locally

From the repository root:

```bash
python3 -m http.server 8000 --directory presentation
```

Open <http://localhost:8000/>. Direct `presentation/index.html` opening also works.

## Present

| Control | Behavior |
| --- | --- |
| Right Arrow / PageDown | Next slide in the current section |
| Left Arrow / PageUp | Previous slide in the current section |
| Space | Next slide, or native activation when a button is focused |
| Enter | Native activation of a focused link or button |
| Home | First slide in the current section |
| End | Q&A: the end of the main presentation, including from the appendix |
| N | Toggle presenter notes |
| F | Toggle browser fullscreen |
| P | Browser print / save as PDF |
| ? | Toggle keyboard help |
| Escape | Close notes/help; otherwise return from appendix to Q&A. The browser also owns Escape for fullscreen exit. |

Click the slide's left/right edges, use navigation buttons, or swipe horizontally.
The progress bar jumps within the current section; its keyboard activation advances
one slide. Pointer interaction does not disable arrow or page-key shortcuts. Native
Space/Enter activation and browser modifier shortcuts are preserved.

The URL fragment and optional local storage preserve the current slide by ID.
Notes are off by default. When enabled, the slide fits beside a scrollable notes
panel rather than behind it. **Notes are visible on this same browser screen:**
close them before sharing/projecting the audience view. The help overlay deliberately
covers the slide until dismissed. The source label remains visible in the footer.

## Main talk and appendix

**15 main slides + 5 appendix slides = 20 slides total.**

1. Title
2. Challenge
3. Project approach — the roadmap
4. Local verification
5. ECS instead of EKS — workload fit
6. Final architecture
7. Infrastructure as Code — bootstrap versus disposable runtime
8. Access and security — human profile versus automation OIDC
9. CI/CD
10. Testing and repeatable verification
11. Recovery
12. Idempotency
13. Does it work? — four evidence groups
14. What I learned
15. Questions? — repository and QR

Aim for a 10–12 minute main talk. Use the speaker notes for transitions, not as a
script to read word for word; keep deeper limitations and implementation detail
for jury questions. Allow the most time for architecture, delivery and recovery.

Normal Next navigation **stops at Questions?**, including keyboard, click-edge,
progress and swipe navigation. Choose **Explore appendix** on that screen to enter:

- A — ECS / EC2 / EKS
- B — Terraform / release ownership
- C — Network flow
- D — OIDC / release controls
- E — Sources and scope boundaries

The appendix counter is separate (`A 1 / 5`). Its **Q&A** button or **End** returns
immediately to Questions?; **Escape** also returns when no overlay is open.
Direct appendix fragment links remain supported. Printing includes both sections.

## QR asset

`assets/github-qr.png` encodes exactly:

<https://github.com/yinon-mitin/Status-Page>

The local PNG is 740×740 pixels with black modules, a white background, medium
error correction and a four-module quiet zone. The deck displays it at 400×400
logical pixels. It has no overlaid logo and requires no external QR API.

To regenerate with the QA environment below:

```bash
python presentation/tools/generate_qr.py
```

## Browser QA

QA tools are optional developer dependencies, not presentation dependencies.
Install them in a virtual environment outside the published `presentation/` tree:

```bash
python3 -m venv /tmp/status-page-deck-qa
source /tmp/status-page-deck-qa/bin/activate
python -m pip install -r presentation/tools/requirements-qa.txt
python -m playwright install chromium
python presentation/tests/test_deck.py
DECK_URL=http://localhost:8000/ python presentation/tests/test_deck.py
python presentation/tools/qa_deck.py http://localhost:8000/ /tmp/status-page-deck-local
```

The regression suite exercises the full main/appendix route, focused controls,
notes, help, fullscreen, navigation keys, link activation and progress boundaries.
The layout audit screenshots every slide at **1920×1080, 1366×768 and 1280×720**,
checks idle/hover text bounds, SVG bounds, assets, footer overlap and browser errors,
decodes the rendered QR at each size, and verifies the PDF page count. Review the
screenshots as well as the report: DOM bounds cannot establish visual quality.

After publishing, repeat against the real repository subpath, not just local HTML:

```bash
DECK_URL=https://yinon-mitin.github.io/Status-Page/ python presentation/tests/test_deck.py
python presentation/tools/qa_deck.py https://yinon-mitin.github.io/Status-Page/ /tmp/status-page-deck-live
```

Also use Firecrawl Interact for a live walkthrough and keyboard sequence. The P
regression test intercepts the print request to avoid a modal dialog; the layout
audit separately generates a real Chromium PDF. Native print dialogs, physical
projection and camera scanning still warrant a final check on the jury equipment.

## Print / PDF

Press **P** or use the browser print dialog. Disable browser headers/footers and
enable background graphics. The stylesheet emits **20 landscape 16:9 pages**,
including appendix slides, and excludes controls and presenter notes.

## GitHub Pages

`.github/workflows/pages.yml` publishes only `presentation/`. It does not invoke
AWS, Terraform or lifecycle scripts. This deck is maintained on
`docs/timeless-public-repository`; presentation publication must not dispatch the
production release workflow or push application changes to `main`.

Live URL: <https://yinon-mitin.github.io/Status-Page/>

Pages is configured for **GitHub Actions**. For a fork, select that source under
Repository Settings → Pages, then run the Pages workflow.

## Evidence boundaries

The main claim is a repeatable engineering method: understand → package and verify
→ design and declare → secure and deliver → prove recovery, convergence and teardown.

The AWS evidence describes a **historical rehearsal**, not a permanently running
service. The runtime was intentionally destroyed after verification to stop recurring
cloud cost. Bootstrap/recovery assets are separate from the disposable runtime.

There are two production images, reused across three application roles. Local
Compose has six running services but only four explicit health checks; the deck
keeps that distinction despite broader wording in the historical summary.

The source proves an approved AWS CLI profile and exact-account validation. It does
not prove the operator's credential source; IAM Identity Center/SSO is explained as
the intended human-authentication model, not an enforced or verified repository control.
GitHub Actions OIDC is an implemented automation identity path.

Appendix repository links are intentionally pinned to the inspected source revision
`a9cd8682cf4df53ee8c0cf723869c7a46f9ddabc`, rather than following potentially divergent
`main`. QR/title/closing links use the canonical project URL. Sources include
`docs/DELIVERY_EVIDENCE.md`, `docs/PRODUCTION_LIFECYCLE.md`, `docs/ARCHITECTURE.md`,
Terraform, workflows, lifecycle scripts and automation tests. Executable source
wins when prose and implementation disagree.
