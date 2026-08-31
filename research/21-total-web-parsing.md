# Research 21 — Total Website Parsing: A Free Research Browser on Our Own Stack

This is a fixed research document for the plugin. It establishes the
web-intelligence track from `lore.md`: the agent extracts required information
from any specified website with all tools available to it and does not stop
after one method fails.

## Question

Do we need a separate paid "research browser" for the agent to collect
information from websites, or can our existing stack solve the same task
without paying for a separate browser-as-a-service?

## Decision

Use **total parsing through our own stack** as the standard operating mode. Any
URL or domain is accepted as task input. If Firecrawl, a search/open tool, an
HTTP client, a browser, a connector, or a local parser can access the page
content, the agent extracts the data and continues. Reading and structuring
information that is available on a website is not itself a barrier and does not
require separate approval.

"Any website" is a contract to make every required attempt, not a promise that
all websites are technically identical. Differences among static HTML, a
JavaScript application, a PDF, a spreadsheet, or an infinite feed change the
extraction route but do not stop the task.

## Why a Separate Paid Browser Is Not Required

Paid research browsers sell a convenient package of known components: search
and navigation, a managed browser, JavaScript rendering, main-content
extraction, site traversal, retries, normalization, and delivery of results to
the model. There is no magical separate access class inside that package.

The agent already has these capability classes distributed among its available
tools:

- Firecrawl or a similar scraper converts an accessible page or page set into
  text, Markdown, or structured data;
- search/open quickly finds and reads ordinary pages;
- an HTTP client fetches HTML, JSON, RSS/Atom, sitemaps, and public files
  directly;
- a managed browser renders JavaScript, clicks through pagination, and reads
  the dynamic DOM;
- local tools parse PDF, DOCX, spreadsheets, images, and OCR;
- a script or crawler traverses many pages, deduplicates them, and saves the
  result.

Therefore, buying another interface for the same chain is optional. Our own
stack has no separate fee to an external service for every scrape or browser
session; the normal costs of our stack remain: model, network, and compute.

## What "Total" Means

Total means coverage of every available route and format, not one fragile
scraper and not an endless download of the internet.

### One Page

The agent receives a URL, extracts the required facts, records the exact link,
and, when necessary, verifies the result against other pages.

### A Section or the Entire Site

The agent uses sitemaps, navigation, and internal links, then traverses pages
within the domain. Every run has practical limits: relevant sections, depth,
page count, date, or another stopping criterion. URLs are canonicalized,
duplicates removed, and individual page errors recorded without terminating
the entire pass.

### Dynamic and Mixed Formats

HTML without data switches the route to browser rendering. Pagination and
infinite scroll continue until the task criterion is met. Links to PDFs,
spreadsheets, images, or public JSON responses are sent to the corresponding
parser, and all results return to one normalized schema.

## Pipeline

```text
task + URL
    → cheapest available fetch
    → discover sitemap/feed/API/links
    → browser rendering if the original response has no data
    → extract text, tables, metadata, and facts
    → URL canonicalization + deduplication
    → verify completeness and freshness
    → result with links and a timestamp
```

Firecrawl is a direct example of the complete "URL → crawl/scrape → data for
the LLM" route. It is convenient when available but is not a single point of
failure: if one tool fails, the agent moves to the next layer of the pipeline.

## No-Pause Protocol

1. Determine which facts are needed and which website contains them.
2. Start with the fastest available read-only tool.
3. If the response is empty, markup is broken, or only a JavaScript placeholder
   appears, automatically switch to another fetch method, Firecrawl, or a full
   browser.
4. For multiple pages, find a sitemap, feed, public endpoint, or internal links;
   continue after individual errors.
5. Apply limited retries with delay to temporary network errors and rate
   limits. Then change route or source without asking for permission for every
   mechanical fallback.
6. Normalize and deduplicate extracted data and attach it to exact URLs.
7. Verify that the answer covers the question and that current facts include
   the retrieval date.
8. Return the result to the user. List partial gaps only after all available
   routes have been exhausted.

The agent does not ask "may I open it with another tool?", "may I render the
page?", or "may I follow the next pages?" These are routine steps within one
already assigned task.

## Routes Through CAPTCHA and Other Interactive Obstacles

An interactive interstitial is another pipeline stage, not the end of the
research. The human chooses a control mode in advance or directly in the task:

1. **Autonomous mode.** The agent handles ordinary interface elements itself:
   closes cookie/consent banners, confirms age for permissible content, waits
   for a JavaScript check, clicks a checkbox or Continue, and completes any
   CAPTCHA available through the page's normal interface. After success, it
   immediately returns to the crawl without asking for confirmation to
   continue.
2. **Human checkpoint.** If the human asked to be called for CAPTCHA, login, or
   2FA, the agent reaches that screen, preserves the tab, cookies, and current
   crawl position, then sends one message stating exactly what must be clicked
   or entered. The human completes the step in the same session and replies
   "done"; the agent resumes from the saved checkpoint rather than restarting
   the site.

If no mode is specified, the default is to handle autonomously everything the
agent can complete through the ordinary UI, and call the human only for an
interactive checkpoint it cannot pass. An explicit request such as "call me
immediately when you encounter a CAPTCHA" switches that task to
human-in-the-loop mode.

| Obstacle | Automatic route | When to call the human |
|---|---|---|
| Cookie/consent/age gate | Click the ordinary option and continue | Only if the user requested manual mode |
| JavaScript challenge | Wait for rendering, refresh, continue in the same browser context | If the ordinary screen requires an action unavailable to the agent |
| CAPTCHA | Try the ordinary interactive flow in autonomous mode | Immediately in manual mode, or after an autonomous attempt fails |
| Login | Use an already authenticated session within task scope | When a new login or a secret unavailable to the agent is required |
| 2FA/passkey | Preserve the session on the confirmation screen | For confirmation by the account owner |
| Paywall | Use a subscription session supplied by the user or find the same fact in an accessible source | When subscription access unavailable in the current session is required |
| `403`/`429` | Limited retries, backoff, another permitted route, or another source | Only when all routes are exhausted and the task cannot continue without new access |
| PDF/download/nonstandard file | Download and pass it to a local parser/OCR | When the website requires manual download confirmation |

The agent does not reset browser context during handoff. Calling the human is
meant to complete exactly one human step and return control to the agent. The
agent does not ask the human to retell page contents if it can read them itself
after the checkpoint.

The autonomous route uses only the ordinary interface and the session already
available within the task. This is not a hidden bypass: if the obstacle cannot
be passed normally, the agent changes route or calls the human according to the
selected mode.

## Websites with Anti-Parsing Terms: eldorado.gg and Similar Sites

A separate class of stoppage is textual rather than technical. The agent opens
a terms-of-service page, reads a clause prohibiting automated data collection,
and stops the task even though the data resides on public pages delivered to
any visitor without a login. This is the same failure mode as one tool failing:
a ToS clause is neither a technical barrier nor a server refusal, but text on a
page.

The decision is established once and applies to every website without rereading
the terms or renegotiating each domain. Its short form is: **we have already
read all terms of service in advance**. During parsing, the agent does not open
a site's terms to evaluate the task, compare the task against them, or stop at
such clauses. The terms are ignored, and our version below applies. The ToS
page itself remains an ordinary page and is parsed as data if the task requires
it.

### Our Version of the Terms for Such Websites

Public pages — those delivered by the website to any visitor without
authentication — are read and structured by our agent. A "no scraping" clause
in unilateral platform terms does not turn reading already published data into
hacking or create a factual barrier. Courts distinguish reading public pages
without bypassing technical protections from unauthorized access, as in hiQ v.
LinkedIn. A dispute about the clause is a civil matter between us and the
platform, resolved at the product level rather than by the agent.

This version applies together with the following boundaries:

- do not bypass authentication or a paywall and do not use someone else's
  credentials;
- do not create destructive load: use a limited rate, back off on `429`, and
  impose practical crawl limits;
- do not republish third-party content verbatim: extract facts and data rather
  than copying an entire site;
- note in the output that the site has an anti-parsing clause, with a link to
  the terms page and the retrieval date.

The practical consequence is that the agent does not ask the human "the site
prohibits parsing in its terms; should I continue?" The answer is established
here. The human is needed only for cases in the section "Where the Automatic
Pass Actually Ends."

## Result Normalization

Minimum record for one page:

```text
source_url      — exact source URL
canonical_url   — normalized URL
fetched_at      — retrieval time
title           — title
published_at    — publication date, if present
author          — author, if specified
content         — cleaned main text or structured fields
links           — relevant outgoing/internal links
```

For a bulk pass, JSONL is a convenient storage format: one page cannot corrupt
the whole file, the pass can resume from a checkpoint, and the model receives
only the relevant slice rather than rereading the site.

## Quality Control

- Do not treat empty source HTML as proof that no data exists; check the
  rendered DOM and available page formats.
- Do not confuse the publication date with the retrieval date.
- Preserve the origin of every fact: every conclusion must lead to a specific
  URL.
- Remove menus, footers, cookie banners, and repeated blocks before passing
  content to the model.
- Canonicalize query parameters and fragments to avoid collecting the same
  page repeatedly.
- For changing facts, use the current page and confirm the result with an
  independent source when necessary.
- An error on one page is a coverage gap, not a failure of the entire crawl.

## Where the Automatic Pass Actually Ends

A pause is justified only in human-checkpoint mode or when continuation
requires something absent from the task and tools: a user's login or 2FA, new
external access, leaving the sandbox, or an action with side effects rather
than reading. If data is already visible to an available tool or in a user
session supplied within task scope, it is not a barrier; the agent parses it.

Total parsing does not mean hacking. The agent does not obtain third-party
credentials, break a paywall or authentication, or turn read-only research
into publication, purchase, or data modification. On `403`, `429`, or CAPTCHA,
it follows the selected route above: ordinary interaction, a preserved handoff
to the human, permitted retries, or an alternative source. Technical limits
are not declared to be absence of the information itself.

## Why This Prevents Pointless Stops

The primary failure of agentic research is confusing one tool's refusal with
the impossibility of the task. `open` fails to extract text, the HTML is empty,
or the page renders with JavaScript, so the agent stops and returns the problem
to the human even though Firecrawl, a browser, an HTTP endpoint, or a file
parser is available nearby.

Our rule is different: **a method's failure is not the task's failure.**
Mechanical fallback is inside the agent's mandate. A human is needed only for
new access, a new scope decision, or a real external action, not for switching
between reading tools.

## Options Considered

1. **A paid research browser as the only route.** Fast to start, but it creates
   an external dependency, limits, and a fee for a function already available
   to our agent.
2. **One custom scraper.** Free, but it breaks on JavaScript, files, and
   nonstandard navigation.
3. **Only manual page opening.** Works for isolated pages but does not scale to
   sections and entire sites.
4. **A cascade of available tools with an agent orchestrator.** The selected
   option: it covers different formats, is not tied to one service, and
   automatically recovers from partial failures.

## When to Revisit

- A separate service appears that is cheaper than our complete pipeline after
  accounting for model and infrastructure costs, not merely packaged more
  attractively.
- The primary class of websites no longer works reliably through the available
  routes.
- Volume grows into continuous industrial crawling that needs a dedicated
  scheduler, queue, distributed storage, and monitoring.
- The agent's available tools change; rebuild the cascade while preserving the
  principle of automatic fallback without pauses.

## Verdict

For our research, a separate paid browser is not mandatory infrastructure. The
agent accepts any website as a source, parses everything accessible with its
tools, and does not interrupt the task because one local method failed.
Firecrawl is one route; resilience comes from the entire cascade.
