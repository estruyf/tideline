# Filing behaviour

The contract both apps implement. [app/](../app) is the macOS reference
implementation in Swift; [windows/](../windows) is the Windows one in Rust.
Where the two platforms cannot agree, the difference is written down here
rather than discovered later.

Anything in this document is covered by the shared fixtures in
[fixtures/](../fixtures) so the two stay in step without sharing a build.

## Before the first sweep

**The folder is not read until someone asks for it.** Reading a protected
folder is what raises the platform's permission prompt, so a fresh install
reads nothing at all: no sweep, no measurement, no scan. The window opens
first, says what the permission is for, and the prompt arrives only when the
button asking for it is pressed. An app that fires a system alert before it has
introduced itself is asking a question with no context attached.

Once asked, that is remembered, and later launches probe as normal — a granted
permission does not need announcing twice.

Filing is opt-in. A fresh install has agreed to nothing, and nothing is swept —
not on launch, not on a folder change, not on the daily timer — until someone
has said yes once. The window asks, with the rule it would follow and what that
first sweep would do to the folder as it stands; the answer is remembered and
never asked for again.

The enabled switch and this answer are separate: the switch pauses and resumes
filing, the answer is whether filing was ever agreed to. Both must be yes.

A preview is the exception, because a preview is how the question gets
answered: it moves nothing, so it runs before consent as well as after.

An install that predates the question is treated as having answered it. It has
been filing for weeks, and an update is no reason to stop and ask.

## A sweep

One sweep reads the root folder — never a subfolder — and decides, per entry,
whether it moves and where to. In order:

1. **Skip the folders we own.** A name matching `^\d{4}-\d{2}(-\d{2})?$` is a
   dated folder this app made. A name matching an enabled routing rule or an
   enabled type rule is a destination folder. Neither is ever filed away.
2. **Skip the user's list.** Exact names (`Inbox`) or globs (`*.dmg`).
3. **Skip partial downloads** by extension: `crdownload`, `download`, `part`,
   `partial`, `opdownload`, `tmp`, `temp`, `aria2`.
4. **Skip hidden entries.**
5. **Skip folders** entirely when *file folders too* is off. A `.download`
   bundle is skipped either way.
6. **Read the stamp** under the *sort by* setting (below). No stamp, no move.
7. **Skip anything inside the grace window.** `start_of_day(stamp)` must be
   strictly before `start_of_day(now) - keep_recent_days`.
8. **Skip anything still being written.** See *settling*.
9. **Route it.** In order: the first enabled routing rule whose tests match
   claims it and gives the folder its name; failing that, an enabled type rule
   claiming the extension does; failing both, the folder is the stamp formatted
   as `%Y-%m-%d` (daily) or `%Y-%m` (monthly).

A rule decides *where*, never *when* — a `.dmg` downloaded today still sits
loose until it clears the grace window; it just lands in `Installers/` rather
than a dated folder when its time comes.

Entries are processed in ascending name order so a run is reproducible.

## Routing rules

A type rule claims a file by its extension, which is enough for a `.dmg` and
useless for an invoice: an invoice is a PDF like every other PDF. What marks it
out is what it is called, or where it came from.

A routing rule is a folder in the root and an ordered list of tests. The rule's
`match` says how many of them have to agree — `any`, the default, or `all`. Rules
are tried in list order, first match wins, and the whole set is tried before the
type rules — otherwise `Documents` would swallow an invoice before `Invoices`
ever saw it.

A rule may also carry a `title`: what a window calls it in a list, when that is
not simply its folder. It is a label and nothing else — no engine reads it, and
a rule without one is known by its folder. It exists because two rules may
legitimately send files to one folder, and a list showing both as `Receipts`
cannot be reordered with any confidence.

A test is a field and a pattern:

| Field | Matched against |
| --- | --- |
| `name` | The entry's own name, extension included |
| `where_from` | Each URL the download was recorded as arriving from, in turn |

The pattern grammar is the skip list's — `*`, `?`, `[a-z]`, `[!abc]` — so
`*invoice*` means "contains" and no second operator is stored.

A window may still *offer* one. The macOS editor asks for a field, an operator
and the words — *Name · contains · invoice* — and composes the glob from them:
`contains` is `*value*`, `starts with` is `value*`, and *matches pattern* hands
the glob over whole. That is presentation and nothing more. What is written down
is a pattern, both engines read a pattern, and a pattern whose middle holds a
wildcard reads back as itself rather than as words it cannot be said in.

### Case

**A test ignores case unless it says otherwise.** Setting `matchCase` on a test
turns that off and compares exactly.

The default is the opposite of the skip list's, where a pattern is
case-sensitive on macOS and insensitive on Windows. The two ask different
questions: a skip pattern names a file you can already see in the folder, and
follows the filesystem's own rules about case, while a rule is a hunt for a word
that could have been typed either way. `Invoice-*`, copied out of Finder from
the file that prompted the rule, still has to find `invoice-0042.pdf` from the
next supplier along — and because a rule runs unattended for months, the day it
quietly stops matching is not a day anybody notices.

It is a setting rather than something inferred from the pattern. Guessing —
lower-case means insensitive, a capital means exact — reads well in a search
box, where a wrong guess shows up as an empty result you retype immediately. A
rule gives no such feedback, so the difference has to be visible in the rule
itself.

Ignoring case means folding **ASCII `A`–`Z` only**, on both platforms and in
every locale. That is what the skip list already does on Windows, it makes
`FACTUUR` and `factuur` the same word, and it deliberately leaves `Ä` and `ä`
as different ones. Full Unicode folding is locale-dependent, and two engines
disagreeing about the dotted `İ` in a Turkish locale is exactly the kind of
divergence this document exists to prevent.

Patterns are otherwise compared against the name as the platform hands it over.
macOS returns decomposed names, so a non-ASCII letter typed into a pattern may
not match the file it was copied from; a pattern that sticks to ASCII and leans
on `*` for the rest has no such problem.

### Any, and all

A rule set to `any` claims a file when one of its tests matches. A rule set to
`all` claims it only when every one of them does — "an invoice *and* from
Stripe", which under `any` would take every Stripe export as well.

**A test with an empty pattern is dropped before the question is asked**, in
both modes. It already claims nothing under `any`; under `all` it would stop the
rule matching anything at all, and a half-written condition in a settings window
must not silently switch a rule off. A rule left with no filled-in test claims
nothing, whichever mode it is in.

`all` is stored as `"match": "all"`. **A rule with no `match` written down means
`any`**, and so does an unreadable value: that is what every rule saved before
the setting existed meant, and `all` only ever narrows what a rule catches. A
rule that quietly stops firing after an upgrade is not something anybody
notices.

### Where the file came from

Both platforms record the URL a download arrived from, and both keep it when the
file is moved. That is what lets a rule recognise a file someone renamed by
hand, and what lets a rule written today match something that arrived last
month.

| | |
| --- | --- |
| macOS | `com.apple.metadata:kMDItemWhereFroms` — a binary plist holding the source URL and the referrer |
| Windows | The `Zone.Identifier` alternate data stream — `HostUrl` and `ReferrerUrl` |

Each is a list of zero or more URLs, and a test matches if any one of them
matches. The URLs are **percent-decoded before matching**, because the
interesting word is often escaped inside a query string: a download whose only
mention of what it is reads `?path=%2Ffacturen%2F2026%2F` should be findable by
someone who typed `*/facturen/*`.

Match against the whole URL, not the host. A receipt can arrive from
`logitech.com` with the word that identifies it buried in the path
(`api.global-e.com/Document/CustomerReceiptInvoice?…`), and a Stripe invoice
arrives from an S3 bucket whose hostname mentions neither Stripe's product nor
the file.

None of this is guaranteed to be there. A file saved out of a mail client,
dropped in over AirDrop or fetched with `curl` may carry no URL at all, and a
mail attachment carries the mailbox rather than the sender. An absent list is
not an error and not a match: the rule moves on to its next test, and the file
to the next rule.

### What a rule may not do

A rule is consulted last, so it rescues nothing. The skip list, hidden entries,
partial downloads, the missing stamp, the grace window and the settling check
have all had their say before step 9 is reached.

A rule's destination is a **folder name in the root**, never a path, and it is
held to the same name rules as a type folder: not empty, at most 60 characters,
no `/` or `:`, no leading dot, and nothing that could be mistaken for a dated
folder. Filing writes inside the watched folder and nowhere else — that is what
lets putting things back be total, and what stops a sweep leaving a file
somewhere the app no longer looks. Moving a file out of the watched folder is
*collecting*, below, and it never happens on a timer.

A rule's folder is owned exactly as a type folder is: never filed away, opened
by the reviews, and emptied by putting things back — including the folder of a
rule that is currently switched off, since files put there while it was on are
still sitting in it.

## Settling

A file whose contents changed in the last **30 seconds** is assumed to still be
in flight and is left for the next sweep. Between 30 seconds and 10 minutes the
size is read twice, 1.5 s apart, and the file moves only if the two agree — a
slow writer can leave a stale timestamp between flushes. Past 10 minutes it is
taken as settled.

Folders are never settle-checked; a folder's own timestamp says nothing about
what is being written inside it.

## Collisions

Nothing is ever overwritten. `report.pdf` into a folder that already has one
becomes `report-1.pdf`, then `report-2.pdf`, counting up until a name is free.
The extension is preserved; a file with no extension just gains the suffix.

## Dates

| Setting | macOS | Windows |
| --- | --- | --- |
| `added` | `addedToDirectoryDateKey` — Finder's "Date Added" | NTFS creation time |
| `created` | `creationDateKey` | NTFS creation time |
| `modified` | `contentModificationDateKey` | last write time |

**This is the one real divergence.** macOS records when an item arrived *in the
folder it sits in now*, independent of how old the file itself is — an
AirDropped photo keeps the day it was shot as its creation date, so creation
date would file it under the wrong day.

Windows has no equivalent attribute. NTFS creation time is set when the file is
created in that folder, which for a download is the moment it arrived — so for
the case this app exists to handle the two agree. They diverge when a file is
*moved* into the folder from elsewhere on the same volume, where Windows
preserves the original creation time and macOS would record the move.

Consequence: on Windows `added` and `created` resolve to the same value. The
setting is still offered under both names so the two apps' settings files stay
interchangeable, and the UI says what it does.

Each basis falls back when its attribute is missing: `added` → created →
modified, `created` → modified, `modified` → created.

## Clearing

Only folders matching the dated pattern are ever considered — loose files and
folders the user named are invisible to it.

Age is measured from the **end of the period the folder is named for**, not the
folder's own timestamp, which filing bumps every time it drops something new
inside. A folder named `2026-08` is a month old at the end of September, not
at the end of August.

The newest `keep_newest` folders are held back whatever their age, so a long
quiet spell can never empty the root.

Folders go to the recycle bin (macOS Trash, Windows Recycle Bin) — never
`unlink`. A setting the user regrets is a drag back out, not a restore from
backup.

## Review scope

Duplicate, large-file and catch-up reviews, and collecting, look in the root
plus the folders this app made — dated folders, type folders and routing-rule
folders, including the folders of rules that are currently switched off, since
files put there while a rule was on are still sitting in them. A folder the user
made is never opened.

## Putting it back

The mirror of a sweep, and the only way filing is undone in one gesture.

It reads the same folders a review does — the dated folders, the type folders
and the routing-rule folders, the folders of switched-off rules included — and
takes their
**immediate contents** back into the root. A folder that was filed as one thing
comes back as one thing; nothing is unpacked. A folder the user made is never
opened.

The rules that govern a sweep govern this too: a name already taken in the root
counts up, and nothing is deleted. A folder this empties goes to the recycle
bin, **including a type or rule folder** — clearing leaves those alone, but an
empty `Installers/` is not something the folder had before the app, so putting
things back puts that back as well.

A real restore then **pauses filing**. The next sweep would move back exactly
what was just taken out, and that is not an argument to have with someone's
downloads folder. Resuming is the switch in the header; the answer to the
question above stands, so it is not asked again.

Preview mode covers it: it lists what would come back and moves nothing.

## Collecting

Called **Move out** in the macOS window. The operation keeps its own name here
and in the code, where one word for find-then-deposit is worth having.

Filing sorts the watched folder. Collecting takes things out of it — the
quarter's invoices into an accounting folder, a shoot's photos onto an external
drive — and it is the only operation that writes anywhere but the root.

It never runs on its own. Not on the timer, not when the folder changes, not
after a sweep. It happens when someone opens it, asks for something, and ticks
what they meant.

**Finding.** A collection starts from a routing rule, a type rule, or a set of
tests typed on the spot, and it searches the same places the reviews do: the
root, the dated folders and the destination folders, the folders of
switched-off rules included. A folder the user made is never opened.

This is what makes a rule retroactive. The rule written today finds the invoices
already filed under `2026-07-02/`, which is the one thing filing alone can never
fix — a sweep only ever sees what is loose in the root.

Unlike a sweep, collecting **ignores the grace window**. A sweep waits because
nobody asked it to hurry; here somebody did, and a file that arrived an hour ago
is as collectable as one from June.

That is the only guard being asked by hand lifts. The skip list, hidden entries,
partial downloads and *file folders too* all still hold: asking for something is
a reason to skip the waiting, not a reason to take a kind of thing the app has
been told to leave alone.

A set of tests that turns out to be right can be **saved as a rule** from here,
which is the intended way to write one: see what it catches, then keep it.

**What a rule's own folder contributes.** A hunt started from a rule also offers
everything sitting in that rule's folder, whether or not the file itself answers
to a test. A file dragged there by hand, or one that matched a pattern since
edited, is still that rule's doing. These are marked as having matched only
because of where they sat, listed apart from the real matches, and **never
ticked** — the app is guessing, and says so.

**Choosing.** Nothing moves that was not ticked. Everything is grouped by the
test that claimed it, so a pattern that is too loose shows up as one long group
of things that do not belong together, and a match on a URL is distinguishable
at a glance from a match on the name. That is how a false positive gets noticed
before it lands in somebody's accounts.

**Where it lands.** A destination is a folder, remembered as a bookmark rather
than as a path so it survives a rename or an unmounted volume, and it may carry
a template:

```
~/…/Invoicing/{yyyy}/quarter {q}/in
```

| Token | |
| --- | --- |
| `{yyyy}`, `{yy}` | The year |
| `{mm}` | The month, `01`–`12` |
| `{dd}` | The day, `01`–`31` |
| `{q}` | The quarter, `1`–`4` |

Tokens resolve **per file**, from that file's own stamp under the current *sort
by* setting. A batch that straddles the end of a quarter therefore lands in two
folders, which is the answer the accounting wanted and the one a single fixed
destination could not give.

A destination outside the watched folder raises the platform's own permission
prompt the first time it is written to. That is asked for when the destination
is saved, with the folder named, rather than in the middle of a move.

**The rules that govern a sweep govern this too.** A name already taken counts
up — `report.pdf`, `report-1.pdf` — and nothing is overwritten or deleted. A
dated folder that a collection empties goes to the recycle bin, since an empty
day is not a day. A type or rule folder that a collection empties does not: it
is a standing destination, and the next sweep will fill it again.

**Undoing.** A collection is one batch to one destination and is recorded as
one, so it comes back in one gesture: each file to the folder it was taken from,
or to the root if that folder has since gone, under the same collision rules.
This matters more here than anywhere else in the app, because these are the only
files that leave the folder the app watches, and putting things back cannot
reach them.

**Preview mode covers it**, as it covers everything that moves: the list is
built and shown, and nothing is opened for writing.

## Preview mode

A preview walks the folder exactly as a real sweep does and reports what it
would have done, having opened nothing for writing. The planner is shared
between the two so the preview and the sweep cannot drift.
