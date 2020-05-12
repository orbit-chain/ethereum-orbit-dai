const Web3 = require('web3')
const assert = require('assert')

const BN = Web3.utils.BN
BN.fromEth = ethValue => new BN(ethValue).mul(new BN('1000000000000000000'))
BN.prototype.over = function (divisor) {
  return this.div(new BN(divisor))
}

const extendedAssert = new Proxy(assert, {
  get(target, property) {
    const handler = {
      equalByComparator: function (actual, expected, message, comparator) {
        let err = message
        if (!(message instanceof Error)) {
          err = new target.AssertionError({
            message: message,
            actual: actual.toString(),
            expected: expected.toString(),
          })
        }
        return target.ok(comparator(actual, expected), err)
      },
      equal: function (actual, expected, message) {
        if (typeof actual.eq === 'function') {
          return this.equalByComparator(actual, expected, message, (a, b) => a.eq(b))
        }
        return target.equal(actual, expected, message)
      },
      strictEqual: function (actual, expected, message) {
        if (typeof actual.eq === 'function') {
          return this.equalByComparator(actual, expected, message, (a, b) => a.eq(b))
        }
        return target.strictEqual(actual, expected, message)
      },
      eventArgsEqual: function (actual, expected, message) {
        const actualArguments = actual.args
        Object.entries(expected).forEach(([arg, value]) => {
          this.strictEqual(actualArguments[arg], value, `${message}: ${arg}`)
        }, this)
      },
    }
    return Object.hasOwnProperty.call(handler, property) ? handler[property] : target[property]
  },
})

const getEventsByName = (transaction, eventName) => {
  if (eventName != null) {
    if (typeof eventName === 'string') return transaction.logs.filter(log => log.event === eventName)
    if (eventName instanceof Array) return transaction.logs.filter(log => new Set(eventName).has(log.event))
  }
  return transaction.logs
}

const toEthString = weiValue => {
  let ethValue = weiValue
  while (ethValue.length <= 18) ethValue = `0${ethValue}`
  return `${ethValue.substr(0, ethValue.length - 18)}.${ethValue.substr(-18)}`
}

const asyncSleep = ms => new Promise(resolve => setTimeout(resolve, ms))

module.exports = {
  BN,
  getEventsByName,
  assert: extendedAssert,
  toEthString,
  asyncSleep,
}
