# Vendored dependencies

All dependencies are ordinary source files. Builds need no package download or
submodule initialization. Upstream files are unmodified; `SHA256SUMS` records
their contents (run `sha256sum -c lib/SHA256SUMS` from the project root).

| Dependency | Release | Commit | Included files | License |
| --- | --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/69c8def5f222ff96f2b5beff05dfba996368aa79) | v5.1.0 | `69c8def5f222ff96f2b5beff05dfba996368aa79` | ERC20, IERC20, IERC20Metadata, Context, IERC6093 errors, LICENSE | MIT |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505) | v1.9.7 | `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | Solidity files under src/, LICENSE-MIT, LICENSE-APACHE | MIT or Apache-2.0 |

OpenZeppelin supplies the production ERC-20 implementation. forge-std is only a
test dependency. No external libraries need bytecode linking.
