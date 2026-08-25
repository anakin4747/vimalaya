# Viewing an Email Chain with Himalaya

Himalaya has no built-in thread/chain viewer. There is no `envelope thread`,
`message thread`, or similar command, and the search DSL has no clause for
`Message-ID` / `In-Reply-To` / `References`. To view a chain you have to walk
those headers manually across individual commands.

## Background

Threading is not computed by himalaya; it's just standard RFC 5322 headers
embedded in each message:

- `Message-ID` — unique ID of the message itself.
- `In-Reply-To` — the `Message-ID` of the message being replied to.
- `References` — the full ordered list of ancestor `Message-ID`s in the
  chain.

## Manual command sequence

1. **Find the starting message's envelope ID** in a mailbox:

   ```
   himalaya envelope list -m INBOX
   ```

   or narrow it down with:

   ```
   himalaya envelope search subject "some subject"
   ```

2. **Read its headers** to get `Message-ID`, `In-Reply-To`, and `References`:

   ```
   himalaya message read <ID> --raw
   ```

   or, for structured output:

   ```
   himalaya message read <ID> --json
   ```

3. **Walk backward (ancestors)**: the `References` header lists every
   ancestor `Message-ID`, oldest first. For each one, since there's no
   "search by Message-ID" command, you must:

   ```
   himalaya envelope search subject "<same normalized subject>"
   ```

   then, for each candidate envelope ID returned, run:

   ```
   himalaya message read <candidate-ID> --json
   ```

   and manually compare its `Message-ID` header against the one you're
   looking for.

4. **Walk forward (replies)**: same problem in reverse. List or search the
   mailbox, then for each candidate:

   ```
   himalaya message read <candidate-ID> --json
   ```

   and check whether its `In-Reply-To` or `References` header contains the
   `Message-ID` of the message you're tracking.

5. **Repeat** steps 3–4 for each newly discovered message until you've
   walked the whole chain from root to leaves.

6. **Read each message's body** once you know its ID:

   ```
   himalaya message read <ID>
   ```

## Summary

There is no shortcut: reconstructing a chain with himalaya alone means
repeatedly calling `envelope search` / `envelope list` plus `message read
--json` for every message, and manually cross-referencing `Message-ID`,
`In-Reply-To`, and `References` yourself.
