
---

As you scroll down a `vimalaya <mailbox> mailbox` buffer, the plugin will
asynchronously fetch more until reaching the end of the envolopes.

---

Upon reaching the bottom of the envolopes the last line should say:
```
END OF ENVOLOPES
```

---

`G` should bring you to the bottom of the envolopes, not just the bottom of the
currently loaded envolopes.

---

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

K hover headers in email buffers show the specification for that header

---

Date and time of envelopes are more human readable

---

all the subjects of envelopes are aligned instead of depending on the length of
the date/time

---

Red syntax highlighting for emails not found in cache meaning it may be
mispelled or not a valid email address

---

b4 integration and git send mail support

---

the header info of an email is folded by default to have that easily accessible
but not the main focus

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

:Mail reuses active mailbox buffers
:Mail reuses hidden mailbox buffers

If a mailbox buffer is already open, pressing enter on that mailbox from the
main menu should just switch to that buffer instead creating a new one

---

