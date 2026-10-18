# Native input equivalence for the final release commit

| Identity | Commit |
| --- | --- |
| Fully executed native gate | `67b3f60138074823857a3f86f4d517c87f2ac9e2` |
| Final release source | `8300cabcb5859fcc74c3ff613a2c530a47c01f30` |

The final source reuses the completed native result through exact execution
input equivalence. It was **not rerun** in a new VM.

The 62 direct native code, compilation and runtime inputs are byte-identical:
54 top-level Swift sources, the two Swift harnesses, two verification scripts,
shared cleanup/process libraries, App entitlements and DisplayProbe. Each hash
also matches the actual archive used by the completed native run. The five
outer/guest QA runner hashes remain identical. Both the complete workflow build
job and its Replay AppKit step are unchanged.

The full 157-file archive is **not identical**: 156 inputs match, while
`tests/test_release_workflow_contract.py` changed. That Python file is not
compiled or executed by the native gates; it is only read by archive integrity
hashing. The other changed file is the hosted install workflow, whose changes
are outside the unchanged native build job. The new workflow guards and Python
contract tests require their own validation on the final release commit.

The retained native result is 440/438/432 interaction checks and 20000 stress
iterations, all passed. Matched-tail checks pass in each mode. Its resource
audit and owned VM deletion are retained and hashed by this proof; both
original TestLab VMs were preserved. No new test VM or App was created for the
equivalence check, and earlier evidence was not modified.

See:

- `native-execution-inputs.sha256`: the exact 62-input footprint.
- `native-input-equivalence.json`: tested/release hashes, archive difference,
  unchanged workflow invocation and QA runner hashes.
- `owned-source-verification.json`: atomic dispatch proof, with
  `testedCommit` distinct from `releaseSourceCommit`,
  `executionInputsIdentical=true`, `allArchiveInputsIdentical=false`, and hashes
  of the retained execution/cleanup evidence.

This proof covers the native gate only. Hosted CI, candidate builds, installation
matrix and publication must still pass on the final release commit.
