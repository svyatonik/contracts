const Promise = require("bluebird");
const SetOwnedWithMigration = artifacts.require("./OwnedKeyServerSetWithMigration.sol");
const ServerKeyRetrievalService = artifacts.require("./SecretStoreServerKeyRetrievalService.sol");

import {recoverPublic} from './helpers/crypto';

require('chai/register-expect');
require('truffle-test-utils').init();

contract('ServerKeyRetrievalService', function(accounts) {
  let nonKeyServer = accounts[5];

  // Key servers data.
  let server1 = { ip: '127.0.0.1:12000' };
  let server2 = { ip: '127.0.0.1:12001' };
  let server3 = { ip: '127.0.0.1:12002' };
  let server4 = { ip: '127.0.0.1:12003' };
  let server5 = { ip: '127.0.0.1:12004' };

  function initializeKeyServerSet(contract) {
    server1.address = accounts[0];
    server1.public = recoverPublic(accounts[0]);
    server2.address = accounts[1];
    server2.public = recoverPublic(accounts[1]);
    server3.address = accounts[2];
    server3.public = recoverPublic(accounts[2]);
    server4.address = accounts[3];
    server4.public = recoverPublic(accounts[3]);
    server5.address = accounts[4];
    server5.public = recoverPublic(accounts[4]);

    contract.addKeyServer(server1.public, server1.ip);
    contract.addKeyServer(server2.public, server2.ip);
    contract.addKeyServer(server3.public, server3.ip);
    contract.addKeyServer(server4.public, server4.ip);
    contract.addKeyServer(server5.public, server5.ip);
  }

  describe("ServerKeyRetrievalService", () => {
    let setContract;
    let serviceContract;

    beforeEach(() => SetOwnedWithMigration.new()
      .then(_contract => setContract = _contract)
      .then(() => ServerKeyRetrievalService.new(setContract.address))
      .then(_contract => serviceContract = _contract)
    );

    // SecretStoreServiceBase tests

    it("should return correct value from keyServersCount", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.keyServersCount())
      .then(c => assert.equal(5, c))
      .then(() => setContract.removeKeyServer(server3.address))
      .then(() => serviceContract.keyServersCount())
      .then(c => assert.equal(4, c))
    );

    it("should return correct index from requireKeyServer", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => setContract.removeKeyServer(server3.public, server3.ip))
      .then(() => serviceContract.requireKeyServer(server1.address))
      .then(i => assert.equal(0, i))
      .then(() => serviceContract.requireKeyServer(server2.address))
      .then(i => assert.equal(1, i))
      .then(() => serviceContract.requireKeyServer(server3.address))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    // ServerKeyRetrievalServiceClientApi tests

    it("should accept server key retriveal request", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        { value: web3.toWei(100, 'finney') }))
      .then(receipt => assert.web3Event(receipt, {
        event: 'ServerKeyRetrievalRequested',
        args: {
          serverKeyId: "0x0000000000000000000000000000000000000000000000000000000000000001"
        }
      }, 'Event is emitted'))
    );

    it("should reject server key retrieval request when fee is not paid", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000001"))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should reject server key retrieval request when not enough fee paid", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        { value: web3.toWei(50, 'finney') }))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should reject server key retrieval request when there are too many pending requests", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        { value: web3.toWei(100, 'finney') }))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000002",
        { value: web3.toWei(100, 'finney') }))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000003",
        { value: web3.toWei(100, 'finney') }))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000004",
        { value: web3.toWei(100, 'finney') }))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000005",
        { value: web3.toWei(100, 'finney') }))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000006",
        { value: web3.toWei(100, 'finney') }))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000007",
        { value: web3.toWei(100, 'finney') }))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000008",
        { value: web3.toWei(100, 'finney') }))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000009",
        { value: web3.toWei(100, 'finney') }))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should reject duplicated server key retrieval request", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        { value: web3.toWei(100, 'finney') }))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        { value: web3.toWei(100, 'finney') }))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    // ServerKeyRetrievalServiceKeyServerApi tests

    it("should publish retrieved server key if all servers respond with same value", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        { value: web3.toWei(100, 'finney') }))
      // 3-of-5 servers are required to respond with the same threshold value:
      // 1) 3-of-5 servers are responding with the same threshold value
      // 2) by that time last response already have support of 3 (when only 2 is required) => retrieved
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 1,
        { from: server1.address }))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 1,
        { from: server2.address }))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 1,
        { from: server3.address }))
      .then(receipt => assert.web3Event(receipt, {
        event: 'ServerKeyRetrieved',
        args: {
          serverKeyId: "0x0000000000000000000000000000000000000000000000000000000000000001",
          serverKeyPublic: "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        }
      }, 'Event is emitted'))
    );

    it("should publish retrieved server key if some servers respond with different public values", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        { value: web3.toWei(100, 'finney') }))
      // 3-of-5 servers are required to respond with the same threshold value:
      // 1) KS1 responds with (P1, 3). 3-threshold support is 1
      // 2) KS2 responds with (P2, 3). 3-threshold support is 2
      // 3) KS3 responds with (P1, 3). 3-threshold support is 3 => threshold is 3. (P1, 3) support is 2
      // 4) KS4 responds with (P1, 3). (P1, 3) support is 3
      // 5) KS5 responds with (P1, 3). (P1, 3) support is 4
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 3,
        { from: server1.address }))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000003", 3,
        { from: server2.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 3,
        { from: server3.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 3,
        { from: server4.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 3,
        { from: server5.address }))
      .then(receipt => assert.web3Event(receipt, {
        event: 'ServerKeyRetrieved',
        args: {
          serverKeyId: "0x0000000000000000000000000000000000000000000000000000000000000001",
          serverKeyPublic: "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        }
      }, 'Event is emitted'))
    );

    it("should publish retrieved server key if some servers respond with different threshold values", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        { value: web3.toWei(100, 'finney') }))
      // 3-of-5 servers are required to respond with the same threshold value:
      // 1) KS1 responds with (P1, 3). 3-threshold support is 1
      // 2) KS2 responds with (P1, 10). 3-threshold support is 1
      // 3) KS3 responds with (P1, 3). 3-threshold support is 2
      // 4) KS4 responds with (P1, 3). (P1, 3) support is 3 => threshold is 3. (P1, 3) support is 3
      // 5) KS5 responds with (P1, 3). (P1, 3) support is 4
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 3,
        { from: server1.address }))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 10,
        { from: server2.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 3,
        { from: server3.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 3,
        { from: server4.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 3,
        { from: server5.address }))
      .then(receipt => assert.web3Event(receipt, {
        event: 'ServerKeyRetrieved',
        args: {
          serverKeyId: "0x0000000000000000000000000000000000000000000000000000000000000001",
          serverKeyPublic: "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        }
      }, 'Event is emitted'))
    );

    it("should publish retrieved server key if public is stabilized before threshold", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        { value: web3.toWei(100, 'finney') }))
      // 3-of-5 servers are required to respond with the same threshold value:
      // 1) KS1 responds with (P1, 1). 1-threshold support is 1
      // 2) KS2 responds with (P1, 1). 1-threshold support is 2. (P1, 1) support is 2, enough for 1-threshold
      // 3) KS3 responds with (P2, 1). 1-threshold support is 3 => threshold is 1. P1 already has enough support && we publish it
      //  even though KS3 has responded with P2 && at the end P2 could end having enough confirmations
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 1,
        { from: server1.address }))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 1,
        { from: server2.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000003", 1,
        { from: server3.address }))
      .then(receipt => assert.web3Event(receipt, {
        event: 'ServerKeyRetrieved',
        args: {
          serverKeyId: "0x0000000000000000000000000000000000000000000000000000000000000001",
          serverKeyPublic: "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        }
      }, 'Event is emitted'))
    );

    it("should raise retrieval error if many servers respond with different public values before threshold stabilized", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        { value: web3.toWei(100, 'finney') }))
      // 3-of-5 servers are required to respond with the same threshold value:
      // 1) KS1 responds with (P1, 3). 3-threshold support is 1
      // 2) KS2 responds with (P2, 3). 3-threshold support is 2
      // 3) KS3 responds with (P3, 3). 3-threshold support is 3 => threshold is 3 => we need 4 nodes to agree upon same public value
      //   => max public support is 1 and there are only 2 nodes left to vote => agreement is impossible
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 3,
        { from: server1.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000003", 3,
        { from: server2.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000004", 3,
        { from: server3.address }))
      .then(receipt => assert.web3Event(receipt, {
        event: 'ServerKeyRetrievalError',
        args: {
          serverKeyId: "0x0000000000000000000000000000000000000000000000000000000000000001"
        }
      }, 'Event is emitted'))
    );

    it("should raise retrieval error if many servers respond with different public values after threshold stabilized", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        { value: web3.toWei(100, 'finney') }))
      // 3-of-5 servers are required to respond with the same threshold value:
      // 1) KS1 responds with (P1, 2). 2-threshold support is 1
      // 2) KS2 responds with (P2, 2). 2-threshold support is 2
      // 3) KS3 responds with (P3, 2). 2-threshold support is 3 => threshold is 2 => we need 3 nodes to agree upon same public value
      // 4) KS4 responds with (P4, 2). max public support is 1 and there are only 1 node left to vote => agreement is impossible
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 2,
        { from: server1.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000003", 2,
        { from: server2.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000004", 2,
        { from: server3.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000005", 2,
        { from: server4.address }))
      .then(receipt => assert.web3Event(receipt, {
        event: 'ServerKeyRetrievalError',
        args: {
          serverKeyId: "0x0000000000000000000000000000000000000000000000000000000000000001"
        }
      }, 'Event is emitted'))
    );

    it("should raise retrieval error if many servers respond with different threshold values", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.retrieveServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        { value: web3.toWei(100, 'finney') }))
      // 3-of-5 servers are required to respond with the same threshold value:
      // 1) KS1 responds with (P1, 1). 2-threshold support is 1
      // 2) KS2 responds with (P1, 2). 2-threshold support is 2
      // 3) KS3 responds with (P1, 3). 2-threshold support is 3 => threshold is 2 => we need 3 nodes to agree upon same public value
      // 4) KS4 responds with (P1, 4). max threshold support is 1 and there is only 1 node left to vote => threshold agreement is impossible
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 1,
        { from: server1.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 2,
        { from: server2.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 3,
        { from: server3.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
      .then(() => serviceContract.serverKeyRetrieved("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", 4,
        { from: server4.address }))
      .then(receipt => assert.web3Event(receipt, {
        event: 'ServerKeyRetrievalError',
        args: {
          serverKeyId: "0x0000000000000000000000000000000000000000000000000000000000000001"
        }
      }, 'Event is emitted'))
    );

    // Administrative API tests
  });
});
