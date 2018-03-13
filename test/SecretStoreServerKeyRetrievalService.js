const Promise = require("bluebird");
const SetOwnedWithMigration = artifacts.require("./OwnedKeyServerSetWithMigration.sol");
const ServerKeyRetrievalService = artifacts.require("./SecretStoreServerKeyRetrievalService.sol");

import {recoverPublic} from './helpers/crypto';

require('chai/register-expect');
require('truffle-test-utils').init();

contract('ServerKeyRetrievalService', function(accounts) {
  let nonKeyServer = accounts[3];

  // Key servers data.
  let server1 = { ip: '127.0.0.1:12000' };
  let server2 = { ip: '127.0.0.1:12001' };
  let server3 = { ip: '127.0.0.1:12002' };

  function initializeKeyServerSet(contract) {
    server1.address = accounts[0];
    server1.public = recoverPublic(accounts[0]);
    server2.address = accounts[1];
    server2.public = recoverPublic(accounts[1]);
    server3.address = accounts[2];
    server3.public = recoverPublic(accounts[2]);

    contract.addKeyServer(server1.public, server1.ip);
    contract.addKeyServer(server2.public, server2.ip);
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
      .then(c => assert.equal(2, c))
      .then(() => setContract.addKeyServer(server3.public, server3.ip))
      .then(() => serviceContract.keyServersCount())
      .then(c => assert.equal(3, c))
    );

    it("should return correct index from requireKeyServer", () => Promise
      .resolve(initializeKeyServerSet(setContract))
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

    // Administrative API tests
  });
});
