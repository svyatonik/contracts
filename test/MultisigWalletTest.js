import {increaseTimeTo, duration} from './helpers/increaseTime.js';
import {assertEvent, assertNoEvent} from "./helpers/assertEvent";

const Promise = require("bluebird");
const Wallet = artifacts.require("./Wallet.sol");

const getBlockNumber = Promise.promisify(web3.eth.getBlockNumber);
const getBlock = Promise.promisify(web3.eth.getBlock);

contract('MultiSig Wallet', function(accounts) {
  let defaultUser = web3.eth.accounts[0];
  let signer1 = web3.eth.accounts[1];
  let signer2 = web3.eth.accounts[2];
  let signer3 = web3.eth.accounts[3];
  let recipient = web3.eth.accounts[4];
  let otherUser = web3.eth.accounts[5];
  let newOwner = web3.eth.accounts[6];
  let otherUser2 = web3.eth.accounts[7];

  describe("Setup", () => {


    let wallet;
    const dailyLimit = 123;
    beforeEach(() => {
      return Promise.resolve()
        .then(() => Wallet.new([signer1, signer2, signer3], 2, dailyLimit))
        .then((_wallet) => wallet = _wallet)
        .then(() => wallet.sendTransaction({from: defaultUser, value: 10000}))
    });

    it("should have inited", function() {
      return Promise.resolve()
        .then(() => wallet.m_numOwners())
        .then(n => assert(n.equals(3), `Should have 3 signers, got ${n}`))

        .then(() => wallet.m_required())
        .then(n => assert(n.equals(2), `Should require 2 signers, got ${n}`))

        .then(() => wallet.m_dailyLimit())
        .then(n => assert(n.equals(123), `Should have dailyLimit of 123, got ${n}`))
    });

    it("allows signers to add an owner", function() {
      return Promise.resolve()
        .then(() => wallet.addOwner(newOwner, {from: signer1}))
        .then(result => assertNoEvent(result, "OwnerAdded"))
        .then(() => wallet.isOwner.call(newOwner))
        .then(result => assert(!(result === true), "new owner should not be a new owner yet"))

        .then(() => wallet.addOwner(newOwner, {from: signer2}))
        .then(result => {
          assertEvent(result, "OwnerAdded", {
            newOwner: newOwner
          })
        })
        .then(() => wallet.isOwner.call(newOwner))
        .then((b) => assert(b === true, "newOwner should have been added"));
    });

    it("allows signers to remove an owner", function() {
      return Promise.resolve()
        .then(() => wallet.removeOwner(signer3, {from: signer1}))
        .then(result => assertNoEvent(result, "OwnerRemoved"))
        .then(() => wallet.isOwner.call(signer3))
        .then(result => assert((result === true), "signer3 should still be an owner"))

        .then(() => wallet.removeOwner(signer3, {from: signer2}))
        .then(result => {
          assertEvent(result, "OwnerRemoved", {
            oldOwner: signer3
          })
        })
        .then(() => wallet.isOwner.call(signer3))
        .then((b) => assert(b === false, "signer3 should have been removed"));
    });

    it("does NOT allow non-signers to remove an owner", function() {
      return Promise.resolve()
        .then(() => wallet.removeOwner(signer3, {from: otherUser}))
        .then(() => wallet.removeOwner(signer3, {from: otherUser2}))
        .then(result => assertNoEvent(result, "OwnerRemoved"))
        .then(() => wallet.isOwner.call(signer3))
        .then((b) => assert(b === true, "signer3 should not have been removed"));
    });

    it("allows signers to change the required number of signers", function() {
      return Promise.resolve()
        .then(() => wallet.changeRequirement(3, {from: signer1}))
        .then(result => assertNoEvent(result, "RequirementChanged"))
        .then(() => wallet.m_required())
        .then(result => assert((result.equals(2)), "requirement should still be 2: " + result))

        .then(() => wallet.changeRequirement(3, {from: signer2}))
        .then(result => {
          assertEvent(result, "RequirementChanged", {
            newRequirement: 3
          })
        })
        .then(() => wallet.m_required())
        .then(result => assert((result.equals(3)), "requirement should be 3"))
    });

    it("does NOT allow required == 0", function() {
      return Promise.resolve()
        .then(() => wallet.changeRequirement(0, {from: signer1}))
        .then(result => assertNoEvent(result, "RequirementChanged"))

        .then(() => wallet.changeRequirement(0, {from: signer2}))
        .then(result => assertNoEvent(result, "RequirementChanged"))

        .then(() => wallet.m_required())
        .then(result => assert((result.equals(2)), "requirement should still be 2"))
    });

    it("does NOT allow required > numSigners", function() {
      return Promise.resolve()
        .then(() => wallet.changeRequirement(4, {from: signer1}))
        .then(result => assertNoEvent(result, "RequirementChanged"))

        .then(() => wallet.changeRequirement(4, {from: signer2}))
        .then(result => assertNoEvent(result, "RequirementChanged"))

        .then(() => wallet.m_required())
        .then(result => assert((result.equals(2)), "requirement should still be 2"))
    });

    it("does NOT allow non-signers to add an owner", function() {
      return Promise.resolve()
        .then(() => wallet.removeOwner(otherUser, {from: otherUser}))
        .then(() => wallet.removeOwner(otherUser, {from: otherUser2}))
        .then(result => assertNoEvent(result, "OwnerAdded"))
        .then(() => wallet.isOwner.call(otherUser))
        .then((b) => assert(b === false, "otherUser should not have been added"));
    });
  });

  describe("Transact", () => {
    let wallet;
    const dailyLimit = 123;
    beforeEach(() => {
      return Promise.resolve()
        .then(() => Wallet.new([signer1, signer2, signer3], 2, dailyLimit))
        .then((_wallet) => wallet = _wallet)
        .then(() => wallet.sendTransaction({from: defaultUser, value: 10000}))
    });

    it("should NOT allow another person to initiate", function() {
      return Promise.resolve()
        .then(() => wallet.execute(recipient, dailyLimit+1, "0x0", {from: otherUser}))
        .then(results => {
          assertNoEvent(results, "Confirmation");
          assertNoEvent(results, "ConfirmationNeeded");
        })
    });

    it("should wait for multiple signatures for amount > dailyLimit", function() {
      return Promise.resolve()
        .then(() => wallet.execute(recipient, dailyLimit+1, "0x0", {from: signer1}))
        .then(results => {
          assertEvent(results, "Confirmation", {
            owner: signer1
          });
          assertEvent(results, "ConfirmationNeeded", {
            initiator: signer1,
            value: 124,
            to: recipient,
            data: "0x"
          });
        })
    });

    it("should execute after confirm", function() {
      let operation;
      let startingBalance;
      return Promise.resolve()
        .then(() => web3.eth.getBalance(recipient))
        .then(_balance => startingBalance = _balance)
        .then(() => wallet.execute(recipient, dailyLimit+1, "0x", {from: signer1}))
        .then(results => {
          operation = results.logs[0].args.operation;
          return wallet.confirm(operation, {from: signer2})
        })
        .then(results => {
          assertEvent(results, "Confirmation", {
            owner: signer2,
            operation: operation,
          });
          assertEvent(results, "MultiTransact", {
            owner: signer2,
            operation: operation,
            value: dailyLimit+1,
            to: recipient,
            data: "0x",
            created: "0x0000000000000000000000000000000000000000"
          });
        })
        .then(() => web3.eth.getBalance(recipient))
        .then(_balance => assert(startingBalance.plus(dailyLimit+1).equals(_balance), "recipient should have received funds"))
    });

    it("should NOT allow a non-signer to confirm", function() {
      let operation;
      let startingBalance;
      return Promise.resolve()
        .then(() => web3.eth.getBalance(recipient))
        .then(_balance => startingBalance = _balance)
        .then(() => wallet.execute(recipient, dailyLimit+1, "0x", {from: signer1}))
        .then(results => {
          operation = results.logs[0].args.operation;
          return wallet.confirm(operation, {from: otherUser})
        })
        .then(results => {
          assertNoEvent(results, "Confirmation");
          assertNoEvent(results, "MultiTransact");
        })
        .then(() => web3.eth.getBalance(recipient))
        .then(_balance => assert(startingBalance.equals(_balance), "recipient should NOT have received funds"))
    });

    it("should transact immediately amount < dailyLimit", function() {
      let startingBalance;
      return Promise.resolve()
        .then(() => web3.eth.getBalance(recipient))
        .then(_balance => startingBalance = _balance)
        .then(() => wallet.execute(recipient, dailyLimit-1, "0x0", {from: signer1}))
        .then(results => {
          assertEvent(results, "SingleTransact", {
            owner: signer1,
            value: dailyLimit-1,
            to: recipient,
            data: "0x",
            created: "0x0000000000000000000000000000000000000000"
          });
        })
        .then(() => web3.eth.getBalance(recipient))
        .then(_balance => assert(startingBalance.plus(dailyLimit-1).equals(_balance), "recipient should have received funds"))
    });

    it("should require confirm when total spent is above the daily limit", function() {
      return Promise.resolve()
        .then(() => wallet.execute(recipient, dailyLimit-1, "0x0", {from: signer1}))
        .then(() => wallet.execute(recipient, 2, "0x0", {from: signer1}))
        .then(results => {
          assertEvent(results, "Confirmation", {
            owner: signer1
          });
          assertEvent(results, "ConfirmationNeeded", {
            initiator: signer1,
            value: 2,
            to: recipient,
            data: "0x"
          });
        })
    });

    it.only("should clear the daily limit", function() {
      let currentTime;
      let startingBalance;
      return Promise.resolve()
        .then(() => getBlockNumber()).then(b => getBlock(b))
        .then(b => currentTime = b.timestamp)
        .then(() => wallet.execute(recipient, dailyLimit-1, "0x0", {from: signer1}))

        // wait one day
        .then(() => increaseTimeTo(currentTime + duration.days(1)))
        .then(() => wallet.execute(recipient, 2, "0x0", {from: signer1}))

        .then(results => {
          assertNoEvent(results, "Confirmation");
          assertNoEvent(results, "ConfirmationNeeded");
          assertEvent(results, "SingleTransact", {
            owner: signer1,
            value: 2,
            to: recipient,
            data: "0x",
            created: "0x0000000000000000000000000000000000000000"
          });
        })
    });
  });
});

function printJson(json) {
  console.log(JSON.stringify(json, null, 2));
}
