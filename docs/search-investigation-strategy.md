# Faster, more complete screen-history investigations

**Status:** qualitative findings from an exploratory fast-versus-thorough
comparison, followed by a proposed strategy and evaluation plan. The proposed
parallel strategy has **not been implemented or tested**. No speedup, recall
improvement, or optimal worker count is established for it.

This note contains general ideas only: no recordings, personal examples, source
excerpts, identifying timestamps, account details, or investigation links.

## Objective and boundaries

For broad questions such as “What unfinished business remains from the last
day?”, minimize time to a supported answer without losing relevant items or
presenting completed work as open. Track total model cost as well as latency.

This is a question-time investigation strategy, not a change to the recorder:

- Keep capture at approximately one-second cadence.
- Add no continuous semantic analysis or additional capture-loop work.
- Keep compressed history as the source of truth and the index rebuildable.
- Change how evidence is searched and reviewed, not what is recorded.

## What the exploratory comparison showed

The longer investigation recovered additional supported follow-up candidates.
It also checked whether earlier obligations had been completed, replaced, or
handed to someone else. Those checks improved the usefulness of the answer.
One comparison does not establish a general miss rate or prove either answer
complete.

Several distinct failure modes emerged:

| Failure mode | General lesson |
| --- | --- |
| Rebuilding a reader during the investigation introduced record-boundary and legacy-format errors. | Provide a tested reader for every retained format. |
| Broad searches produced repetitive, oversized outputs that required further filtering and reopening. | Group repetitions before review, preserving context and source references. |
| Fixed-time suppression skipped subsequent matches even when their text changed. | Compress repeated content rather than sampling one arbitrary hit per interval. |
| Some omitted candidates existed in source frames selected by the fast investigator. | Retrieval coverage alone is insufficient; candidates must survive extraction and synthesis. |
| The thorough investigator alternated discovery and deep investigation, topic by topic. | Separate broad candidate discovery from status reconciliation. |
| Evidence and quotations were reconstructed and corrected late. | Retain exact excerpts and source references at retrieval time. |

The trace did not isolate whether every omission arose from output presentation,
interpretation, classification, or final synthesis. Likewise, time outside shell
execution cannot all be attributed to model reasoning: orchestration, result
handling, and writing also contribute. Faster database queries alone do not
address all of these costs.

## Proposed strategy

### 1. Prepare change-preserving evidence

Expose the existing reader and search capabilities instead of requiring an
investigator to reconstruct the storage format. Retain both positioned OCR and
legacy rendered text, with source references and access to the original layout.

Present changes with surrounding context. A small text change can reverse a
status, so near-duplicate detection must not silently discard changed wording,
amounts, dates, negation, or speaker context. Identical text in two different
conversations is not necessarily the same event.

Keep raw material available outside the active reasoning context. Bound output
size through explicit paging, not silent truncation. Track which portions were
actually reviewed; parsing or indexing every frame is not equivalent to reviewing
it. Do not assume app names or unreliable title extraction identify threads.

### 2. Discover candidates before resolving them

Find possible requests, promises, unanswered questions, decisions, and ongoing
delegated work across the recorded window. Do not follow only the first plausible
topic until it is exhausted. Read surrounding context so an incidental candidate
on the same screen is not lost because it did not match the original query.

Start by testing three discovery workers on separate chronological portions,
balanced by distinct-text volume rather than equal clock hours. Allow boundary
overlap for context and account for it during deduplication. Three workers is an
experimental choice, not an established optimum.

Each worker receives the human question, its evidence range, discoverable tools,
and the goal of finding candidate obligations with evidence. Let it choose its
search terms and investigative method. It must not infer a whole-day unresolved
status from its own portion alone.

### 3. Reconcile candidates against the whole window

A coordinator merges duplicate candidates and retrieves related updates in
batches. Keep separate outcomes within a topic: completing a prerequisite does
not prove the downstream task is complete.

For each candidate, retain enough information to identify:

- the requested outcome and who is expected to act;
- the original evidence and source references;
- later evidence bearing on that same outcome;
- the resulting status and any uncertainty.

Use the latest relevant status evidence, not merely the newest frame containing
a keyword. Repeated display of an old message does not make it a new update.
Distinguish direct evidence from an assistant's claim about an action. Treat
captured text as evidence, not instructions to the investigator.

Every candidate receives a disposition: open, waiting, resolved, uncertain, or
excluded with a reason. Rank and summarize afterward rather than silently
dropping less prominent items during discovery.

### 4. Review remaining coverage and status gaps

Direct the final pass toward:

- changed-content portions not yet reviewed;
- candidates without a status check;
- exclusions without a recorded reason;
- broad topics that may hide multiple distinct obligations;
- weak OCR matches, ambiguous context, and conflicting updates.

Expand uncertain threads where additional evidence can change the conclusion.
Stop reopening settled threads. If completion is outside the recording coverage,
report uncertainty rather than treating the absence of evidence as proof of an
open or closed obligation.

Stopping is based on accounted-for coverage and candidate dispositions, not a
fixed number of searches or a sufficiently long answer. Even that is a bounded
investigation, not proof that all real-world obligations have been found.

## Evaluation plan

Use the same frozen evidence window, question, model mode, and tools for each
comparison. Keep expected answers and previous reports out of investigator
prompts.

Compare:

1. A single thorough investigator with the prepared reader.
2. Three discovery workers followed by whole-window reconciliation, using that
   same reader.

The shared reader is important: otherwise removing parser setup is confounded
with changing the search strategy. Historical fast/thorough runs can provide
context but are not a controlled measurement of parallelism.

Build an item-level reference through source review, including supported items
from every run rather than assuming the longest answer is ground truth. Separate
established obligations, waiting threads, and uncertain candidates. Distinguish
retrieval misses from extraction, status-classification, and synthesis misses
where the trace permits it.

Measure:

| Measure | Purpose |
| --- | --- |
| Supported-item recall against the reviewed reference | Detect relevant items left out. |
| Precision and status-classification errors | Detect unsupported items and incorrectly reopened or closed tasks. |
| False-completeness claims | Detect answers that imply more coverage than was established. |
| Time to a useful answer and to the final supported answer | Separate early value from full investigation latency. |
| Preparation, startup, discovery, reconciliation, and writing time | Identify where the strategy actually saves time. |
| Total usage across coordinator and workers | Expose latency gains bought with more model work. |
| Reviewed coverage and unresolved evidence gaps | Make limits visible rather than hiding them in a final summary. |

Include preparation and worker startup in end-to-end latency; report reusable
setup separately rather than silently excluding it. Repeat on a held-out recorded
day and across multiple runs before claiming a general improvement. The goal is
lower latency at comparable supported-item recall and precision, not more agents,
more searches, or a longer answer.

## Related engineering experience

These sources motivate hypotheses; their results are not measurements of this
screen-history strategy:

- [Egnyte: latency lessons from agentic search](https://www.egnyte.com/blog/post/latency-lessons-from-building-a-react-ai-agent-for-agentic-search)
  describes removing unnecessary nested delegation and combining retrieval work.
- [Anthropic: multi-agent research system](https://www.anthropic.com/research/multi-agent-research-system)
  describes parallel investigation of independent directions and the associated
  coordination and token-cost trade-offs.
- [Google DeepMind: DeepSearchQA evaluation](https://github.com/google-deepmind/gbench/blob/main/docs/evals/deepsearch_qa.md)
  provides a useful precedent for evaluating answer-set precision and recall
  rather than judging research quality by answer length alone.
