const Promise = require("bluebird");
const SetOwnedWithMigration = artifacts.require("./OwnedKeyServerSetWithMigration.sol");
const ServerKeyGenerationService = artifacts.require("./SecretStoreServerKeyGenerationService.sol");

import {recoverPublic} from './helpers/crypto';

require('chai/register-expect');
require('truffle-test-utils').init();

contract('ServerKeyGenerationService', function(accounts) {
  let nonKeyServer = accounts[3];

  // Hardcoded servers for cases when we do not need to sign transactions.
  let server1 = {
    public: '0xd230b17d59a0a3c32e9cdbd55cb64f7d5322f985f854542a7619314364f274cd7984efc0f12d1ad29a0998e936d44e4143c7b8dc0f79ec0580d5b069d1ecacf2',
    private: '0x95698c0184c58f24c3587dda4aedd6ed378729f23fc19f7ca0fde21b3bfe92a2',
    address: '0x484817497433b8f896f4230398140c79d6e71bbe',
    ip: '127.0.0.1:12000'
  };
  let server2 = {
    public: '0x85497867467e7337a86631e23d7c4ef8edc1a7a8701a9065859f874777a257f4d5465d00fd56deb6790cf00bb899720902cc6c8cfeb53ba8399ff606b66e5094',
    private: '0x3b3801207c2d6851d389fccd5e52621e9dbfe2d7aee5f691c350ccc739f0943b',
    address: '0xee613015ccea088566d50a865d49d3ef970442b5',
    ip: '127.0.0.1:12001'
  };
  let server3 = {
    public: '0xd59ebab1811934dbbeb01020aea9bd4850da167c704b4e5310345df77d5ba1196206de1cbb22e299a6c38ab4a7ea1648f2f6a81781fe4e7db31c36317738b2e6',
    private: '0x323f25528bca4eac32e75590ec62a6674240468de6ae7633f580d727642d00a6',
    address: '0xc274fcaf830aa911f1b5a32c8af21c6ee7c3d264',
    ip: '127.0.0.1:12002'
  };

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

  describe("ServerKeyGenerationService", () => {
    let setContract;
    let serviceContract;

    beforeEach(() => SetOwnedWithMigration.new()
      .then(_contract => setContract = _contract)
      .then(() => ServerKeyGenerationService.new(setContract.address))
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

    // ServerKeyGenerationServiceClientApi tests

    it("should accept server key generation request", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(200, 'finney') }))
      .then(receipt => assert.web3Event(receipt, {
        event: 'ServerKeyGenerationRequested',
        args: {
          serverKeyId: "0x0000000000000000000000000000000000000000000000000000000000000001",
          author: accounts[0],
          threshold: 1
        }
      }, 'Event is emitted'))
    );

    it("should reject server key generation request when fee is not paid", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001", 1))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should reject server key generation request when not enough fee paid", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(100, 'finney') }))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should reject server key generation request when threshold is too large", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        2, { value: web3.toWei(200, 'finney') }))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should reject server key generation request when there are too many pending requests", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        0, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000002",
        0, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000003",
        0, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000004",
        0, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000005",
        0, { value: web3.toWei(200, 'finney') }))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should reject duplicated server key generation request", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        0, { value: web3.toWei(200, 'finney') }))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    // ServerKeyGenerationServiceKeyServerApi tests

    it("should publish generated server key", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.serverKeyGenerated("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        { from: server1.address }))
      .then(() => serviceContract.serverKeyGenerated("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        { from: server2.address }))
      .then(receipt => assert.web3Event(receipt, {
        event: 'ServerKeyGenerated',
        args: {
          serverKeyId: "0x0000000000000000000000000000000000000000000000000000000000000001",
          serverKeyPublic: "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        }
      }, 'Event is emitted'))
    );

    it("should not accept generated server key when it is not a valid public", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.serverKeyGenerated("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x01", { from: server1.address }))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should ignore generated server key when there's no request", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.serverKeyGenerated("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        { from: server1.address }))
    );

    it("should not accept generated server key from non key server", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.serverKeyGenerated("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x01", { from: nonKeyServer }))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should not publish server key if got second response from same key server", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.serverKeyGenerated("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        { from: server1.address }))
      .then(() => serviceContract.serverKeyGenerated("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        { from: server1.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
    );

    it("should raise generation error if two key servers are not agreed about generated server key", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.serverKeyGenerated("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        { from: server1.address }))
      .then(() => serviceContract.serverKeyGenerated("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000003",
        { from: server2.address }))
      .then(receipt => assert.web3Event(receipt, {
        event: 'ServerKeyGenerationError',
        args: {
          serverKeyId: "0x0000000000000000000000000000000000000000000000000000000000000001"
        }
      }, 'Event is emitted'))
    );

    it("should raise generation error if at least one key server has reported an error", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.serverKeyGenerationError("0x0000000000000000000000000000000000000000000000000000000000000001",
        { from: server1.address }))
      .then(receipt => assert.web3Event(receipt, {
        event: 'ServerKeyGenerationError',
        args: {
          serverKeyId: "0x0000000000000000000000000000000000000000000000000000000000000001"
        }
      }, 'Event is emitted'))
    );

    it("should fail if generation error is reported be a non key server", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.serverKeyGenerationError("0x0000000000000000000000000000000000000000000000000000000000000001",
        { from: nonKeyServer }))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should not raise generation error if no request", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.serverKeyGenerationError("0x0000000000000000000000000000000000000000000000000000000000000001",
        { from: server1.address }))
      .then(receipt => assert.equal(receipt.logs.length, 0))
    );

    it("should return pending requests", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.serverKeyGenerationRequestsCount())
      .then(c => assert.equal(c, 0))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { from: server1.address, value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000002",
        0, { from: server2.address, value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.serverKeyGenerationRequestsCount())
      .then(c => assert.equal(c, 2))
      .then(() => serviceContract.getServerKeyGenerationRequest(0))
      .then(request => {
        assert.equal(request[0], "0x0000000000000000000000000000000000000000000000000000000000000001");
        assert.equal(request[1], server1.address);
        assert.equal(request[2], 1);
      })
      .then(() => serviceContract.getServerKeyGenerationRequest(1))
      .then(request => {
        assert.equal(request[0], "0x0000000000000000000000000000000000000000000000000000000000000002");
        assert.equal(request[1], server2.address);
        assert.equal(request[2], 0);
      })
    );

    it("should return if response is required", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.isServerKeyGenerationResponseRequired("0x0000000000000000000000000000000000000000000000000000000000000001",
        server1.address))
      .then(isResponseRequired => assert.equal(isResponseRequired, true))
      .then(() => serviceContract.isServerKeyGenerationResponseRequired("0x0000000000000000000000000000000000000000000000000000000000000001",
        server2.address))
      .then(isResponseRequired => assert.equal(isResponseRequired, true))
      .then(() => serviceContract.serverKeyGenerated("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        { from: server1.address }))
      .then(() => serviceContract.isServerKeyGenerationResponseRequired("0x0000000000000000000000000000000000000000000000000000000000000001",
        server1.address))
      .then(isResponseRequired => assert.equal(isResponseRequired, false))
      .then(() => serviceContract.isServerKeyGenerationResponseRequired("0x0000000000000000000000000000000000000000000000000000000000000001",
        server2.address))
      .then(isResponseRequired => assert.equal(isResponseRequired, true))
    );

    it("should reset existing responses when servers set changes", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      // request is created and single key server responds
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.serverKeyGenerated("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        { from: server1.address }))
      .then(() => serviceContract.isServerKeyGenerationResponseRequired("0x0000000000000000000000000000000000000000000000000000000000000001",
        server1.address))
      .then(isResponseRequired => assert.equal(isResponseRequired, false))
      // then we're starting && completing the migration
      .then(() => setContract.completeInitialization())
      .then(() => setContract.addKeyServer(server3.public, server3.ip))
      .then(() => setContract.startMigration("0x0000000000000000000000000000000000000000000000000000000000000001", {from: server1.address}))
      .then(() => setContract.confirmMigration("0x0000000000000000000000000000000000000000000000000000000000000001", {from: server1.address}))
      .then(() => setContract.confirmMigration("0x0000000000000000000000000000000000000000000000000000000000000001", {from: server2.address}))
      .then(() => setContract.confirmMigration("0x0000000000000000000000000000000000000000000000000000000000000001", {from: server3.address}))
      // let's check that response is now required key server 1
      .then(() => serviceContract.isServerKeyGenerationResponseRequired("0x0000000000000000000000000000000000000000000000000000000000000001",
        server1.address))
      .then(isResponseRequired => assert.equal(isResponseRequired, true))
      // now we're receiving response from KS2 && KS3 and still response from KS1 is required
      .then(() => serviceContract.serverKeyGenerated("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        { from: server2.address }))
      .then(() => serviceContract.serverKeyGenerated("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        { from: server3.address }))
      .then(() => serviceContract.isServerKeyGenerationResponseRequired("0x0000000000000000000000000000000000000000000000000000000000000001",
        server1.address))
      .then(isResponseRequired => assert.equal(isResponseRequired, true))
      // now we're receiving response from KS1 and key generated event is fired
      .then(() => serviceContract.serverKeyGenerated("0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
        { from: server1.address }))
      .then(receipt => assert.web3Event(receipt, {
          event: 'ServerKeyGenerated',
          args: {
            serverKeyId: "0x0000000000000000000000000000000000000000000000000000000000000001",
            serverKeyPublic: "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002",
          }
        }, 'Event is emitted'))
    );

    // Administrative API tests

    it("should be able to change fee", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.setServerKeyGenerationFee(10))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(10, 'finney') }))
    );

    it("should not be able to change fee by a non-owner", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.setServerKeyGenerationFee(10, { from: nonKeyServer }))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should be able to change requests limit", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.setMaxServerKeyGenerationRequests(5))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000002",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000003",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000004",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000005",
        1, { value: web3.toWei(200, 'finney') }))
    );

    it("should not be able to change requests limit by a non-owner", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.setMaxServerKeyGenerationRequests(5, { from: nonKeyServer }))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should be able to delete request", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.serverKeyGenerationRequestsCount())
      .then(c => assert.equal(c, 1))
      .then(() => serviceContract.deleteServerKeyGenerationRequest("0x0000000000000000000000000000000000000000000000000000000000000001"))
      .then(() => serviceContract.serverKeyGenerationRequestsCount())
      .then(c => assert.equal(c, 0))
    );

    it("should not be able to delete request by a non-owner", () => Promise
      .resolve(initializeKeyServerSet(setContract))
      .then(() => serviceContract.generateServerKey("0x0000000000000000000000000000000000000000000000000000000000000001",
        1, { value: web3.toWei(200, 'finney') }))
      .then(() => serviceContract.deleteServerKeyGenerationRequest("0x0000000000000000000000000000000000000000000000000000000000000001",
        {from: nonKeyServer}))
      .then(() => assert(false, "supposed to fail"), () => {})
    );
  });
});
