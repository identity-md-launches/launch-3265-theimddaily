# TheImdDaily (TID)

A fixed supply ERC-20 for Ethereum. The constructor mints the complete supply to
its immediate deployer, `msg.sender`, in one mint. In the custom token launch,
that deployer is the factory. No other address receives tokens in the constructor.

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `TheImdDaily` |
| Source | `src/TheImdDaily.sol` |
| Token name | `TheImdDaily` |
| Symbol | `TID` |
| Decimals | `18` |
| Supply in TID | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments | None; ABI constructor argument list is `[]` |
| Constructor ETH value | `0` |
| Intended launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26`, pinned in `foundry.toml` |
| EVM target | Cancun |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | `none` |

The contract requires no external address, oracle, initialization call, library
linking, or post-deployment configuration. Deploy its compiled creation bytecode
directly, without a proxy. The intended factory can use CREATE or CREATE2. A
separate deployment helper would become the initial token holder if it created
the token; it must not be inserted into the launch's deployment path.

The authorized launch process is responsible for the manifest, independent
review, deployment, distribution, liquidity, and explorer source verification.
This project supplies the token source, dependencies, configuration, and tests;
it contains no transaction broadcaster or launch manifest.

## Behavior and assumptions

- Ordinary ERC-20 `transfer`, `approve`, `allowance`, and `transferFrom` behavior
  comes from the vendored OpenZeppelin Contracts v5.1.0 implementation.
- Transfers deliver the exact requested amount. There are no transfer taxes,
  rebases, trading gates, wallet limits, or recipient callbacks.
- The supply is fixed. There are no external mint or burn functions, owner,
  administrator, pausing, blacklisting, seizure, or upgrade mechanisms. The
  deployer has no authority over tokens after transferring them to a holder.
- Successful state-changing ERC-20 calls return `true`. Invalid calls revert
  with OpenZeppelin's ERC-6093 custom errors; failed calls roll back all changes.
- Transfers of zero tokens to a nonzero address succeed and emit `Transfer`.
  Self-transfers preserve the balance. Transfers to the zero address and
  approvals for the zero address revert, including zero amounts.
- Finite allowances decrease on `transferFrom`; `type(uint256).max` is an
  infinite allowance and is not reduced. Even an owner calling `transferFrom`
  for its own balance needs an allowance; it can use `transfer` instead.
- `approve` replaces the caller's existing allowance. Approvals emit `Approval`;
  allowance consumption by `transferFrom` does not emit a second `Approval`, as
  in OpenZeppelin v5. Integrations should query `allowance` for its current value.
- The token rejects ordinary native-currency payments. It has no asset rescue
  function; tokens sent to this token's address or an incompatible recipient
  can be irrecoverable. Forced native-currency transfers cannot be prevented.

Test fixture addresses are local actors only. Production code takes no address
parameters and contains no placeholder recipient or privileged address.

## Launch integration

The factory initially holds all `10^27` units. Distribution is performed by the
launch infrastructure after construction, using standard transfers. The supplied
launch terms allocate 10% to the swarm distributor, 85% to pool seeding, and 5%
to the requester's remainder recipient. The token itself does not enforce or
perform this split. It needs no exemptions for the factory, distributor, pool
manager, or traders because every transfer is exact and permissionless subject
to balances and allowances.

Pool fees and opening-price economics belong to the external launch process;
they are not token transfer fees or token settings. The independent manifest
step copies the provided economics and chain parameters from the assignment.

## After launch

There are no setters, owners, privileged keys, keeper jobs, or maintenance calls.

The launch operator must verify the deployed contract's metadata, decimals,
total supply, initial mint recipient, and source/build settings, then confirm
the factory's distribution and liquidity receipts. No initial supply is reserved
by the token for an application contract or an operator.

Holders control their transfers and spender approvals. Approve only trusted
spenders and preferably exact amounts. When replacing a nonzero allowance,
first revoke it and wait for confirmation before granting the new amount; an
already authorized spender may spend before revocation is confirmed. Lost keys,
mistaken transfers, and malicious approved spenders cannot be repaired by an
administrator. A future change to token behavior requires a new deployment.

## Build and checks

Run from the repository root with Foundry and Solidity 0.8.26 available:

```sh
forge build
forge test
forge fmt --check
```

The compiler version and dependency sources are fixed. All imported sources and
their licenses are included as ordinary files under `lib/`; no package install,
submodule, RPC, or network is needed when the pinned compiler is available.
Dependency provenance and integrity checks are in `lib/DEPENDENCIES.md`.

`foundry.toml` pins the requested fuzz seed:
`0xd2c41230c692f7298799f4bf94d687e21423442974932eedd881d322c9c0d436`.
Each fuzz test runs 1,024 cases. Stateful invariants run 128 sequences of 64
calls per invariant. Tests have independent fixtures, use no environment
variables or fork, and require neither FFI nor filesystem permissions.

| Suite | Coverage |
| --- | --- |
| `test/TheImdDaily.t.sol` | Metadata, exact constructor mint/event, CREATE2 factory ownership of initial supply, transfers/events, zero/full/self transfers, allowance replacement/revocation/consumption, infinite approvals, unauthorized spending, invalid recipients, failed-call rollback, absent administrative functions, distribution/custody flows, and randomized success/failure cases |
| `test/TheImdDaily.invariant.t.sol` | Balances and allowances against an independent accounting model after random transfers, approvals, delegated transfers, and deliberately rejected operations; constant supply and conservation across all actors |

The distribution test models the factory, distributor, custodian, and users with
local fixtures; it tests token movement, not actual Uniswap swaps. The supplied
protected checks were reviewed as acceptance inputs. Executing their full
factory/Uniswap integration requires the external launch harness, its supporting
sources, and the resolved manifest supplied by independent verification.

## Security review scope

The supplied security reference was used to review the constructor and the
reachable ERC-20 implementation. Production code makes no external calls,
uses no signatures or oracles, and has no delegation or upgrade path. Only
the constructor reaches `_mint`; `_burn` is not exposed. Balance and allowance
checks precede their corresponding updates, and any failure reverts the whole
call. OpenZeppelin's unchecked arithmetic is bounded by those checks and total
supply conservation, including self-transfers.

Foundry unit, fuzz, and invariant checks are the local verification scope.
Slither and Mythril are not part of this project's local checks. These checks
are not an independent security audit; independent adversarial review and the
launch's protected integration checks remain part of the release process.
