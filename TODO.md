
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

Maybe this is already resolved?

```
Error: SMTP RCPT TO failed: rejected 555 5.5.2 Syntax error, cannot decode response. For more information, go to

Suggestions:
 - Run with --log-level to enable more verbose logs

E492: Not an editor command: Mess
```

---

<!-- start with a new email or reply with the following: -->
<!---->
<!--     attach: /path/to/directory -->
<!---->
<!-- Then append: -->
<!---->
<!--     attach: /path/to/directory.tar.gz -->
<!---->
<!-- Then write the buffer with `:w` -->
<!---->
<!-- Now vimalaya should make the compressed archive. It should update the -->
<!-- diagnostics to be an info diagnostic (so that makes two diagnostics including the -->
<!-- error diagnostics since the file doesn't exist) that vimalaya is compressing -->
<!-- the file. -->
<!---->
<!-- Once the archive is created vimalaya should have a way to refresh the -->
<!-- diagnostics of the buffer -->
<!---->
<!-- --- -->
<!---->
<!-- any compression format should be supported. If the command to compress fails -->
<!-- due to the command not existing that needs to be shown to the user in the same -->
<!-- fashion as all the other warnings. It should show the entire command that -->
<!-- failed. -->

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

Upon pressing enter on the filename line:

    attachments:
      filename: vimalaya.tar.gz
        mime: application/gzip
        size: 1432415

The UI should be immediately updated to this:

    attachments:
      filename: vimalaya.tar.gz downloading
        mime: application/gzip
        size: 1432415

Once it is downloaded it should be updated to this:

    attachments:
      filename: vimalaya.tar.gz scanning for viruses
        mime: application/gzip
        size: 1432415

Once scanning for viruses is finished it should look like this:

    attachments:
      filename: vimalaya.tar.gz /home/kin/Downloads/vimalaya.tar.gz
        mime: application/gzip
        size: 1432415

If scan failed to run successfully we should see:

    attachments:
      filename: vimalaya.tar.gz scanning for viruses failed
        mime: application/gzip
        size: 1432415

If the scan found viruses we should see:

    attachments:
      filename: vimalaya.tar.gz VIRUS DETECTED - FILE DELETED
        mime: application/gzip
        size: 1432415

---

If the file was downloaded and still exists at the downloaded path do not let
the user download again by emitting a notification that it is already
downloaded or at least that file already exists. And do not download it.

---

Need debouncing on scanning attachments and emit notification if an attachment
is currently being scanned but the user hit enter to try and scan again.
