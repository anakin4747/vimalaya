
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
   at a time.

2. Run `make` to assert that the added test fails. If the test already passes
   since the feature existed before the test then that is fine, continue to 3.
   Do not pipe `make` into any application and do not redirect its output to
   /dev/null. Do not try to run the tests any other way than directly with the
   default make target.

3. Stage the added change to ./tests/vimalaya_spec.lua

4. Run `git status --short` to ensure your commit is only going to include
   modifications to ./tests/vimalaya_spec.lua

5. Then commit your change with a commit that uses a `tests:` prefix

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

4. Stage the added change to ./tests/vimalaya_spec.lua, lua/vimalaya.lua, and
   plugin/vimalaya.lua

5. Run `git status --short` to ensure your commit is only going to include
   modifications to ./tests/vimalaya_spec.lua, lua/vimalaya.lua, and
   plugin/vimalaya.lua

6. Then commit your change with a commit that uses a `feat:` prefix

7. Run `git show` to ensure your commit is atommic and only making the minimal
   modifications necessary to achieve the requested feature.

8. Run `make` to lint check your commit message.

9. Stop.

## Implementation Only Workflows

When to use this workflow:
- When I request only to add the implementation for an already written test
- If I explicitly start a prompt with IOW

1. Follow the Test and Implementation Workflow.

2. If the tests were not tracked with git ensure they are collected into the
   `feat:` commit.

## Test Preservation

- Never weaken, delete, skip, comment out, or replace an existing test assertion
  to make an implementation pass.
- Treat every existing test assertion as required behavior unless the user
  explicitly requests its removal or behavioral change.
- When adapting a test for a new requirement, preserve all prior assertions and
  add assertions for the new behavior.
- If a test conflicts with a requested change, stop and ask the user to confirm
  the intended behavior before modifying the test.

