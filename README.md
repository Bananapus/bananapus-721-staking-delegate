# Bananapus Staking Delegate

`JB721StakingDelegate.sol` manages the issuance and redemption of NFTs representing locked ERC-20 token positions. The delegate is associated with a Juicebox project and is called after the project's ERC-20 terminal is paid.

- The delegate accepts a specified ERC-20 token (`stakingToken`) for staking. This is the only token accepted for payments.
- The delegate issues NFTs to represent locked token positions. These NFTs can be redeemed later, and the contract handles the redemption process.
- The delegate supports multiple tiers of NFTs, each with its own minimum staking threshold. The `tierMultiplier` is used to adjust the staking mechanism to various expected token supplies.
- Each NFT has an associated [lock manager](https://github.com/Bananapus/bananapus-tentacles) (`IBPLockManager`). The lock manager can be set by the owner of the NFT or an approved operator.
- The delegate supports voting delegation. When NFTs are minted, the beneficiary can delegate their votes to another address.

## Usage

use `yarn test` to run tests

use `yarn test:fork` to run tests in CI mode (including slower mainnet fork tests)

use `yarn size` to check contract size

use `yarn doc` to generate natspec docs

use `yarn lint` to lint the code

use `yarn tree` to generate a Solidity dependency tree

use `yarn deploy:mainnet` and `yarn deploy:goerli` to deploy and verify (see .env.example for required env vars, using a ledger by default).

use `forge script script/GenerateTierSVG.sol` to generate an SVG to the path as defined in the script file (default: `./out/image.svg"`)

### Code coverage

Run `yarn coverage`to display code coverage summary and generate an LCOV report

To display code coverage in VSCode:

- You need to install the [coverage gutters extension (Ryan Luker)](https://marketplace.visualstudio.com/items?itemName=ryanluker.vscode-coverage-gutters) or any other extension handling LCOV reports
- ctrl shift p > "Coverage Gutters: Display Coverage" (coverage are the colored markdown lines in the left gutter, after the line numbers)

### PR

Github CI flow will run both unit and forked tests, log the contracts size (with the tests) and check linting compliance.

