usePlugin('@nomiclabs/buidler-truffle5')

const { toEthString } = require('./utils')

const accountBalance = async account => {
  const balance = await web3.eth.getBalance(account)
  return [account, `${balance} Wei`, `${toEthString(balance)} Eth`]
}

// https://buidler.dev/guides/create-task.html
task('accounts', 'Prints the list of accounts with their balances', async () => {
  const accounts = await web3.eth.getAccounts()
  await Promise.all(
    accounts.map(async (account, index) => {
      console.log([index, ...(await accountBalance(account).catch(err => [account, err.message]))].join('\t'))
    })
  )
})

task('balance', 'Prints the balance in each account')
  .addVariadicPositionalParam('accounts', 'ETH address(es)', undefined, undefined, false)
  .setAction(async taskArgs =>
    Promise.all(
      taskArgs.accounts.map(async (account, index) => {
        console.log([index, ...(await accountBalance(account).catch(err => [account, err.message]))].join('\t'))
      })
    )
  )

task('info', 'Prints current network info', async () => {
  const getters = {
    provider: async () => web3.currentProvider._provider._url,
    chainId: web3.eth.getChainId,
    networkType: web3.eth.net.getNetworkType,
    blockNumber: web3.eth.getBlockNumber,
  }

  await Promise.all(
    Object.entries(getters).map(async ([field, valueGetter]) => {
      console.log(`${field}: ${await valueGetter().catch(err => err.message)}`)
    })
  )
})

task('tx', 'Find and prints the transaction with given txid')
  .addPositionalParam('txid', 'Transaction ID', undefined, undefined, false)
  .setAction(async taskArgs => {
    console.log(await web3.eth.getTransaction(taskArgs.txid))
  })

// You have to export an object to set up your config
// This object can have the following optional entries:
// defaultNetwork, networks, solc, and paths.
// Go to https://buidler.dev/config/ to learn more
module.exports = {
  defaultNetwork: 'buidlerevm',
  solc: {
    version: '0.5.12',
    optimizer: { enabled: true, runs: 200 },
  },
  // networks: {
  //   ropsten: {
  //     chainId: 3,
  //     url: 'https://provider-url.somewhere.you.know',
  //     gasMultiplier: 1.2,
  //     accounts: {
  //       mnemonic: 'some mnemonics here if you really want to do use slow ropsten testing',
  //       path: `m/44'/60'/0'/0`,
  //       initialIndex: 0,
  //       count: 4,
  //     },
  //   },
  // },
}
