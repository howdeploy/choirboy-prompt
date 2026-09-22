# Total Website Parsing

## Canon

We defined our research browser as a cascade of tools available to the agent:
Firecrawl/search/open or direct HTTP for fast reading; a full browser for
JavaScript and pagination; file parsers for PDFs, spreadsheets, and images; and
a crawler for sections or complete sites. Any URL may be task input. Failure of
one method does not stop the research: the agent changes route automatically,
continues after isolated errors, deduplicates results, and preserves exact
URLs.

## Goal and Outcome

Question: do we need a separate paid "research browser", or can our existing
stack solve the same task without paying for a separate browser-as-a-service?
Decision: use total parsing through our own stack as the standard operating
mode. The outcome: the agent extracts required information from any specified
website with all tools available to it and does not stop after one method
fails; there is no separate fee to an external service for every scrape or
browser session. Paid research browsers sell a convenient package of known
components; there is no magical separate access class inside that package.

## Architecture and Components

- Firecrawl or a similar scraper: converts an accessible page or page set into
  text, Markdown, or structured data. It is one route, not a single point of
  failure.
- Search/open: quickly finds and reads ordinary pages.
- HTTP client: fetches HTML, JSON, RSS/Atom, sitemaps, and public files
  directly.
- Managed browser: renders JavaScript, clicks through pagination, and reads the
  dynamic DOM.
- Local tools: parse PDF, DOCX, spreadsheets, images, and OCR.
- Script or crawler: traverses many pages, deduplicates them, and saves the
  result.
- Normalized result schema per page: source_url, canonical_url, fetched_at,
  title, published_at, author, content, links. For a bulk pass, JSONL is the
  storage format: one page cannot corrupt the whole file and the pass can
  resume from a checkpoint.

## Decisions and Constraints

- If an available tool can see the information, the agent extracts it without a
  separate approval; reading and structuring information available on a website
  is not itself a barrier.
- "Any website" is a contract to make every required attempt, not a promise
  that all websites are technically identical; format differences change the
  extraction route but do not stop the task.
- CAPTCHA and interactive screens follow the handoff mode chosen by the human:
  autonomous mode (the agent handles ordinary interface elements itself) or a
  human checkpoint (the agent preserves the tab, cookies, and crawl position,
  sends one message, and resumes from the saved state). The default is
  autonomous for everything passable through the ordinary UI.
- Site terms are treated as already reviewed and are not reopened during
  parsing: public pages may be parsed; authentication and paywalls are not
  crossed; request pace is limited; clause disputes are a product-level civil
  matter, as in hiQ v. LinkedIn. The output notes that the site has an
  anti-parsing clause, with a link to the terms page and the retrieval date.
- Total parsing does not mean hacking: no third-party credentials, no breaking
  paywalls or authentication, no turning read-only research into publication,
  purchase, or data modification. No destructive load: limited rate, back off
  on `429`, practical crawl limits. Do not republish third-party content
  verbatim; extract facts.

## Operating Workflow

Pipeline: task + URL → cheapest available fetch → discover sitemap/feed/API/
links → browser rendering if the original response has no data → extract text,
tables, metadata, and facts → URL canonicalization + deduplication → verify
completeness and freshness → result with links and a timestamp.

No-pause protocol: determine the facts needed; start with the fastest read-only
tool; on empty responses, broken markup, or JavaScript placeholders switch
route automatically; for multiple pages find a sitemap, feed, endpoint, or
internal links and continue after individual errors; apply limited retries with
delay, then change route or source without asking; normalize and attach data to
exact URLs; verify coverage and freshness; list partial gaps only after all
available routes are exhausted. An error on one page is a coverage gap, not a
failure of the entire crawl.

## Lessons and Rules

- A fetch failure is not a blocker: switch automatically among Firecrawl, HTTP,
  a browser, or a file parser and continue across the remaining pages. Handle
  CAPTCHA under the human-selected mode.
- Site terms are already reviewed and are not reopened during parsing:
  eldorado.gg once stalled because of a terms page; continue reading public
  pages without repeatedly reevaluating terms, while leaving authentication and
  paywalls untouched.
- Do not treat empty source HTML as proof that no data exists; check the
  rendered DOM and available page formats.
- Do not confuse the publication date with the retrieval date; every conclusion
  must lead to a specific URL.
- Remove menus, footers, cookie banners, and repeated blocks before passing
  content to the model; canonicalize query parameters and fragments.

## Sources

- `lore.md`
- `research/21-total-web-parsing.md`

## Unknowns

- Which concrete tools from the cascade are installed in a given runtime: Not
  established in the sources; verify actual availability per session.
- The default crawl limits (depth, page count) per run: Not established in the
  sources.

## When to Revisit

- A separate service appears that is cheaper than our complete pipeline after
  accounting for model and infrastructure costs.
- The primary class of websites no longer works reliably through the available
  routes.
- Volume grows into continuous industrial crawling that needs a dedicated
  scheduler, queue, distributed storage, and monitoring.
- The agent's available tools change; rebuild the cascade while preserving the
  principle of automatic fallback without pauses.
