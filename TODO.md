
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
