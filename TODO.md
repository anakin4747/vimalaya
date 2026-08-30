
How will the user know that async waiting is happening? Rotate the colors of
the cursor while pending

---

:Mail displays a clear error message if himalaya is not unlocked

---

:Mail chain will open a buffer similar to the mailbox buffer but instead show
all the emails in the same thread as the email buffer you are currently in

This command is only available in email buffers that have chains

Since searching for chains will take time, start searching for chains
asynchronously as soon as the email buffer is opened and contains info that
indicates its a part of a chain

---

Completion of emails in an email buffer after To: and Cc: fields

vimalaya will cache a list of emails referenced in current mailbox buffers so
that this information can be completed quickly

---

syntax highlighting

---

syntax error highlighting on suspiscous emails and email metadata

---

email chains will be highlighted with the same colors in the mailbox buffer

---

Read and unread support

Maybe Unread emails have specific highlighting

---

Need to handle drafts in reply, replyall, forward, and new subcommands

---

caching needs to be implemented to avoid delays going from main menu to mailbox
buffers and going from mailbox buffers to email buffers

---

Red syntax highlighting for emails not found in cache meaning it may be
mispelled or not a valid email address

---

b4 integration and git send mail support
korgalore support
maildir support

---

the header info of an email is folded by default to have that easily accessible
but not the main focus

maybe insert {{{ and set foldmethod=marker to fold the header info

---

Handle unlocking himalaya to not freeze vimalaya

---

:Mail save in a new email saves a draft email with himalaya message compose ... --save
:Mail save in a reply email saves a draft email with himalaya message reply ... --save
:Mail save in a replyall email saves a draft email with himalaya message reply ... --save
:Mail save in a replyall email correctly saves multiple to, cc, and, bcc fields
:Mail save in a forward email saves a draft email with himalaya message forward ... --save

 - For new: build himalaya message compose ... --save <drafts_mailbox>.
 - For reply / replyall: build himalaya message reply <id> --mailbox <mailbox> ... --save <drafts_mailbox> so Himalaya keeps
   threading headers (In-Reply-To, References).
 - For forward: build himalaya message forward <id> --mailbox <mailbox> ... --save <drafts_mailbox>.
 - For replyall, pass explicit repeated --to/--cc gathered from buffer fields (your parser already supports repeated fields
   in lua/vimalaya.lua:307).

---

Maybe move reply's and forwards to use :Mail new instead of reusing the same
buffer???

---

At main menu allow selecting the accounts first

This needs to correctly propagate the email to use in the from:

---

html to markdown conversion for email bodies and set filetype to markdown or if
there is a custom filetype for vimalaya then make that inherit from markdown
somehow

pandoc for this.

---

Before an initial release of this make sure to have a SECURITY.md that uses
security guides from https://github.com/ossf/wg-best-practices-os-developers.git

---

:Mail by default converts html email contents to markdown
:Mail markdown enables the conversion of html email contents to markdown
:Mail html disables the conversion of html email contents to markdown

---

If the file was downloaded and still exists at the downloaded path do not let
the user download again by emitting a notification that it is already
downloaded or at least that file already exists. And do not download it.

---

Need debouncing on scanning attachments and emit notification if an attachment
is currently being scanned but the user hit enter to try and scan again.

---

KK should put the cursor in the hover box the same way it does for language
servers

---

:Mail search - start to think about how you would want to search your email,
the closer to grep the better

---

Displaying the From: email in the mailbox buffer

---

Map grr to list all emails in references with quickfix list of telescope if
telescope is available.

---

Pressing enter on a In-Reply-To: message id or references: message Id should
take you to that email
