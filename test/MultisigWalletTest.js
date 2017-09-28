const Promise = require("bluebird");
const Wallet = artifacts.require("./Wallet.sol");


contract('MultiSig Wallet', function(accounts) {

  describe("Setup", () => {
    let defaultUser = web3.eth.accounts[0];
    let signer1 = web3.eth.accounts[1];
    let signer2 = web3.eth.accounts[2];
    let signer3 = web3.eth.accounts[3];
    let otherUser1 = web3.eth.accounts[4];


    let wallet;
    before(() => {
      return Promise.resolve()
        .then(() => Wallet.new([signer1, signer2, signer3], 2, 123))
        .then((_wallet) => wallet = _wallet)
    });

    it("should have inited", function() {
      return Promise.resolve()
        .then(() => wallet.m_numOwners())
        .then(n => assert(n.equals(3), `Should have 3 signers, got ${n}`))

        .then(() => wallet.m_required())
        .then(n => assert(n.equals(2), `Should require 2 signers, got ${n}`))

        .then(() => wallet.m_dailyLimit())
        .then(n => assert(n.equals(123), `Should have dailyLimit of 3, got ${n}`))
    });
  });
});
