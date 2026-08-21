
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

:Mail reply is NOT a valid subcommand in mailbox buffers
:Mail replyall is NOT a valid subcommand in mailbox buffers
:Mail forward is NOT a valid subcommand in mailbox buffers
:Mail reply is NOT a valid subcommand in main menu buffers
:Mail replyall is NOT a valid subcommand in main menu buffers
:Mail forward is NOT a valid subcommand in main menu buffers

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

:Mail refresh refreshes the main menu buffer
:Mail refresh refreshes mailbox buffers
:Mail refresh is only a subcommand when in a main menu or mailbox buffer
:Mail ref<tab> completes to `:Mail refresh` only in a main menu or mailbox buffer

---

subcommands accept shorthands like ex-commands
:Mail c is a shorthand for :Mail close
:Mail r is a shorthand for :Mail close

---

Need to handle drafts in reply, replyall, forward, and new subcommands

---

caching needs to be implemented to avoid delays going from main menu to mailbox
buffers and going from mailbox buffers to email buffers
