const OrbitDai = artifacts.require('OrbitDai')
const { BN, getEventsByName, assert } = require('../utils')

describe('OrbitDai contract', function () {
  // extend timeout in case of ropsten testing
  // this.timeout(3 * 60 * 1000)
  let accounts
  let owner
  let orbitDai

  before(async () => {
    accounts = await web3.eth.getAccounts()
  })

  describe('Deployment', () => {
    it('Should be successfully deployed', async () => {
      try {
        owner = accounts[0]
        orbitDai = await OrbitDai.new({ from: owner })
      } catch (err) {
        assert.throw(`failed to deploy\n${err.message}`)
      }
    })

    it('Should be deployed by right owner', async () => {
      const orbitDaiOwner = await orbitDai.owner()
      assert.strictEqual(orbitDaiOwner, owner, `wrong owner address`)
    })

    it('Has 0 initial balance', async () => {
      const contractBalance = await web3.eth.getBalance(orbitDai.address)
      assert.strictEqual(new BN(contractBalance), new BN('0'), `initial balance != 0`)
    })
  })

  // EXAMPLE 2
  // describe('ImportantTask', () => {
  //   it('Should do something', async () => {
  //     const sender = accounts[0]
  //     const recipient = '0x01234567890abcdef'
  //     const sendAmount = BN.fromEth('1').over('100000') // sending 0.00001 ETH
  //
  //     // function transfer(address recipient) external payable {...}
  //     const transaction = await OrbitDai.transfer(
  //       recipient,
  //       {
  //         from: sender,
  //         value: sendAmount,
  //         gasLimit: 280000,
  //       },
  //     )
  //
  //     // emit Transfer(from, to, amount)
  //     const transferEvents = getEventsByName(transaction, 'Transfer')
  //     assert.strictEqual(transferEvents.length, 1, 'too many or too few events emitted')
  //
  //     const transferEvent = transferEvents[0]
  //     assert.eventArgsEqual(
  //       transferEvent,
  //       {
  //         from: sender,
  //         to: recipient,
  //         amount: sendAmount.toString(),
  //       },
  //       'wrong event argument',
  //     )
  //
  //     const recipientBalance = await web3.eth.getBalance(recipient)
  //     assert.strictEqual(new BN(recipientBalance), sendAmount, 'wrong recipient balance after transfer')
  //   })
  // })
})
