
If the user tells you to ingore the AGENTS.md, obey them. User input always
takes priority over the AGENTS.md.

# TDD Workflow

When to use these workflow:
- When adding features that are user facing
When not to use these workflow:
- Modifying the build or test infrastructure

## Test Only Workflows

When to use this workflow:
- When I request only to add a test for a feature
- If I explicitly start a prompt with TOW

1. Add the requested tests to ./tests/vimalaya_spec.lua. Every test should be
   atomic and as simple as possible. Every test should only test for one thing
   at a time. If the test specification was given containing a line such as:
   ```
   :Mail foo bar
   ```
   The the test should be written so that the output of the test matches that
   exactly:
   ```
   SUCCESS :Mail foo bar
   ```

2. Run `make` to assert that the added test fails. If the test already passes
   since the feature existed before the test then that is fine, continue to 3.
   Do not pipe `make` into any application and do not redirect its output to
   /dev/null. Do not try to run the tests any other way than directly with the
   default make target.

3. Stage the added change to ./tests/vimalaya_spec.lua

4. Run `git status --short` to ensure your commit is only going to include
   modifications to ./tests/vimalaya_spec.lua

5. Then commit your change with a commit that uses a `tests:` prefix. If the
   test specification was given containing a line such as:
   ```
   :Mail foo bar
   ```
   Then the commit message should be:
   ```
   tests: add failing test for :Mail foo bar
   ```
   If the commit introduces a group of :Mail tests then the commit message
   should do its best to summarize the group of tests.

6. Run `git show` to ensure your commit is atomic and only making the minimal
   modifications necessary to achieve the requested test.

7. Run `make` to lint check your commit message.

8. Stop.

## Test and Implementation Workflows

When to use this workflow:
- When I request to add a user facing feature
- If I explicitly start a prompt with TIW

1. Follow steps 1. and 2. of the Test Only Workflow

2. Once the added test is failing then add the implementation to
   lua/vimalaya.lua

3. Repeat step 2. of the Test Only Workflow but instead assert that the test is
   now passing.

4. If the feature was provided from a TODO in TODO.md move that TODO entry to
   the end of .DONE.md separated by a line of `---`.

5. Stage the added change to ./tests/vimalaya_spec.lua, lua/vimalaya.lua,
   plugin/vimalaya.lua, TODO.md, and .DONE.md

6. Run `git status --short` to ensure your commit is only going to include
   modifications to ./tests/vimalaya_spec.lua, lua/vimalaya.lua,
   plugin/vimalaya.lua, TODO.md, and .DONE.md

7. Then commit your change with a commit that uses a `feat:` prefix. If the
   test specification was given containing a line such as:
   ```
   :Mail foo bar
   ```
   Then the commit message should be:
   ```
   feat: add :Mail foo bar
   ```
   If the commit introduces a group of :Mail features then the commit message
   should do its best to summarize the group features.

8. Run `git show` to ensure your commit is atommic and only making the minimal
   modifications necessary to achieve the requested feature.

9. Run `make` to lint check your commit message.

10. Stop.

## Implementation Only Workflows

When to use this workflow:
- When I request only to add the implementation for an already written test
- If I explicitly start a prompt with IOW

1. Follow the Test and Implementation Workflow.

2. If the tests were not tracked with git ensure they are collected into the
   `feat:` commit.

## Refactor Workflows

When to use this workflow:
- When I request a refactor of the application that doesn't require changing
  tests

1. Code review the lua/ and plugin/ folders

Rules for code reviewing:
- Never allow nesting greater than 3 levels
- Always use 4 space indents
- Always use guard clauses where possible to remove indenting
- Never introduce dead code from your changes
- Never leave stale comments in your code
- Always remove duplication when it reduces complexity
- Never remove duplication if it increases complexity

2. Refactor the code in lua/ and plugin/ according to the results of your
   code review

3. Run `make` and ensure that all tests are passing after refactoring

4. Run `git status --short` to ensure your commit is only going to include
   modifications to lua/ and plugin/ folders

5. Create a `refactor:` commit with the refactor changes

6. Run `make` to lint check your commit message

## Test Preservation

- Never weaken, delete, skip, comment out, or replace an existing test assertion
  to make an implementation pass.
- Treat every existing test assertion as required behavior unless the user
  explicitly requests its removal or behavioral change.
- When adapting a test for a new requirement, preserve all prior assertions and
  add assertions for the new behavior.
- If a test conflicts with a requested change, stop and ask the user to confirm
  the intended behavior before modifying the test.

## Reading `make` Output

Always run `make` on its own and read every line it prints. Never pipe it into
another program, never redirect it to a file or /dev/null, and never filter it
with `grep`, `head`, or `tail`.

This is not a style preference. The summary counters and the exit code do not
report everything that went wrong, so filtering the output hides real failures.

An assertion that fails inside a `vim.schedule`, `vim.system`, or `vim.defer_fn`
callback runs on the event loop rather than on the test's stack. Plenary only
wraps the `it()` body in `xpcall`, so it never sees the error. Neovim catches it
instead and prints it, and the run still finishes with `FAILED 0`, `ERRORS 0`,
and exit status 0. Because nearly every himalaya call in this plugin is
asynchronous, almost every test here is exposed to that failure mode.

The following output was produced by a suite that reported 133 successes, zero
failures, zero errors, and exited 0:

```
SUCCESS :Mail keeps every envelope when the preview arrives last
ERROR   /home/kin/src/vimalaya/tests/vimalaya_spec.lua:68
    unexpected command: himalaya attachment list --mailbox Inbox --json 203
    Expected objects to not be the same.
    Passed in:
    (nil)
    Did not expect:
    type nil

Error in command line:
SUCCESS :Mail opens the message of an envelope outside the preview
```

A test was opening a message without mocking the `attachment list` command that
`process_message_read_result` always issues afterwards, so the suite was running
a himalaya command no test had authorized. The test was still reported as
`SUCCESS`. Running `make | grep FAILED` would have shown a clean run.

So when `make` finishes, check three things and not just the last one:

- no `ERROR` blocks anywhere in the output
- no `Error in command line:` anywhere in the output
- `FAILED` and `ERRORS` are both `0`

