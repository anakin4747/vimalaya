
---

:Mail opens a main menu buffer containing one line per mailbox, this info will be
pulled from:
```sh
himalaya mailbox list --json
```
---

The main menu buffer will be named `vimalaya main menu`

---

The `vimalaya main menu` buffer will be readonly

---

upon pressing enter on one of the mailboxes it will open a mailbox buffer which
contains the envelopes of a bunch of the most recent emails in that mailbox
pulled from:
```sh
himalaya envelope list --mailbox <mailbox> --json --page-size <N>
```

---

The mailbox buffers will be named `vimalaya <mailbox> mailbox`

---

The `vimalaya <mailbox> mailbox` buffer will be readonly

---

The mailbox buffers will be created as they are opened from `vimalaya main menu`

---

Since the main menu buffer will be just a regular buffer you will be able to
jump backwards to the main menu from the mailbox specific buffer with `<C-o>`
and `<C-i>`

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

Pressing enter on an envolope should open up a buffer viewing the email
associated with the envolope pulled from the following command:

```sh
himalaya message read --mailbox <mailbox> <ID>
```

---

Email buffers will be backed to temporary files so that they can be written to

---

Since writing to email buffers is allowed, to get back the original contents of
the email the user must:

1. delete that Email's buffer
2. reopen the Email from a mailbox buffer

---

How will the user know that async waiting is happening? Rotate the colors of
the cursor while pending

---

:Mail reply appends Reply header to email buffers
:Mail replyall appends Reply All header to email buffers
:Mail forward appends Forward header to email buffers

These commands while in an email buffer will append the following to the email buffer:

```
--- Reply ---
To: <original sender>
Cc: <original cc>
Subject: Re: <original subject>

<Response>
```
or
```
--- Reply All ---
To: <original senders>
Cc: <original cc>
Subject: Re: <original subject>

<Response>
```
or
```
--- Forward ---
To: <original senders>
Cc: <original cc>
Subject: Fwd: <original subject>

<Response>
```

Then :Mail send will send the response email to the appropriate recipients and
CCs.

---

Completion for these subcommands will only be available in email buffers

:Mail reply is offered as a possible completion in email buffers
:Mail replyall is offered as a possible completion in email buffers
:Mail forward is offered as a possible completion in email buffers
:Mail reply is NOT offered as a possible completion in mailbox buffers
:Mail replyall is NOT offered as a possible completion in mailbox buffers
:Mail forward is NOT offered as a possible completion in mailbox buffers
:Mail reply is NOT offered as a possible completion in main menu buffers
:Mail replyall is NOT offered as a possible completion in main menu buffers
:Mail forward is NOT offered as a possible completion in main menu buffers

---

:Mail send is offered as a possible completion in email buffers with a reply section
:Mail send is offered as a possible completion in email buffers with a replyall section
:Mail send is offered as a possible completion in email buffers with a forward section
:Mail send is NOT offered as a possible completion in email buffers without a reply, replyall, or forward section
:Mail send is NOT offered as a possible completion in mailbox buffers
:Mail send is NOT offered as a possible completion in main menu buffers

Completion for :Mail send will only be available in email buffers once they
have a `--- Reply ---`, `--- Reply All ---`, or `--- Forward ---` section with
To:, Cc:, and Subject: fields

---

:Mail send fails to send an email if the To: field is empty

---

:Mail send removes the reply, replyall, or forward section from the email buffer after successfully sending the email

---

:Mail new opens a new email buffer with To:, Cc:, and Subject: fields

---

:Mail displays a clear error message if himalaya is not installed

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

The email buffers shall be named `vimalaya <email subject>`

---

:Mail close will close all vimalaya buffers

---

:Mail <tab> will complete subcommands
:Mail cl<tab> will complete to `:Mail close`

---

:Mail shall reuse the same window if the vimalaya main menu buffer is already
open

---

email chains will be highlighted with the same colors in the mailbox buffer

---

:Mail reuses open email buffers

If an email is opened from the mailbox menu then the user jumps back to the
mailbox menu and opens the same email, the email buffer should be reused
instead of creating a new one since it is the same email.

---

Read and unread support

Maybe Unread emails have specific highlighting

---

:Mail refresh refreshes the main menu buffer
:Mail refresh refreshes mailbox buffers
:Mail refresh is only a subcommand when in a main menu or mailbox buffer
:Mail ref<tab> completes to `:Mail refresh` only in a main menu or mailbox buffer

---

:Mail subcommands accept shorthands like ex-commands
