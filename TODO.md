
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

:Mail refresh refreshes the main menu buffer
:Mail refresh refreshes mailbox buffers
:Mail refresh is only a subcommand when in a main menu or mailbox buffer
:Mail ref<tab> completes to `:Mail refresh` only in a main menu or mailbox buffer

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

highlighting a file path and :'<,'>Mail will attach that file to the last email
buffer that was written to if none it should be attached to a new email buffer
as a header field like:

```
--- Reply ---
to: <original sender>
cc: <original cc>
subject: Re: <original subject>
attach: <file path>
```

---

highlighting a file path and :'<,'>Mail will fail if the highlighted text is
not a valid file

---

if several filepaths are highlighted and actually files they are all added with
their own attach: field. One per attachement
