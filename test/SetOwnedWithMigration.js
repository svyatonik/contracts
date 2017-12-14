const Promise = require("bluebird");
const SetOwnedWithMigration = artifacts.require("./OwnedKeyServerSetWithMigration.sol");

import {recoverPublic} from './helpers/crypto';

contract('Set', function(accounts) {
  let owner = accounts[0];
  let nonOwner = accounts[1];
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

  let invalidPublic = '0xd5';
  let migrationId = '0x0000000000000000000000000000000000000000000000000000000000000001';
  let otherMigrationId = '0x0000000000000000000000000000000000000000000000000000000000000002';
  let invalidMigrationId = '0x0000000000000000000000000000000000000000000000000000000000000000';

  function defaultInitialization(contract) {
    contract.addKeyServer(server1.public, server1.ip);
    contract.addKeyServer(server2.public, server2.ip);

    // also check that removeKeyServer works in init phase
    contract.removeKeyServer(server2.address);
    contract.addKeyServer(server2.public, server2.ip);

    contract.completeInitialization();
    return contract;
  }

  function defaultInitializationWithRealAccounts(contract) {
    server1.address = accounts[0];
    server1.public = recoverPublic(accounts[0]);
    server2.address = accounts[1];
    server2.public = recoverPublic(accounts[1]);
    server3.address = accounts[2];
    server3.public = recoverPublic(accounts[2]);

    return defaultInitialization(contract);
  }

  describe("setState", () => {
    let setContract;

    beforeEach(() => SetOwnedWithMigration.new()
      .then(_contract => setContract = _contract)
    );

    it("should return public from current set", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.getCurrentKeyServerPublic(server1.address))
      .then(p => assert.equal(server1.public, p))
    );

    it("should not return public from server not on current set", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.getCurrentKeyServerPublic(server3.address))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should return address from current set", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.getCurrentKeyServerAddress(server1.address))
      .then(p => assert.equal(server1.ip, p))
    );

    it("should not return address from server not on current set", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.getCurrentKeyServerAddress(server3.address))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should return public from migration set", () => Promise
      .resolve(defaultInitializationWithRealAccounts(setContract))
      .then(c => c.removeKeyServer(server2.address))
      .then(() => setContract.startMigration(migrationId, {from: server1.address}))
      .then(() => setContract.getMigrationKeyServerPublic(server1.address))
      .then(p => assert.equal(server1.public, p))
    );

    it("should not return public from server not on migration set", () => Promise
      .resolve(defaultInitializationWithRealAccounts(setContract))
      .then(c => c.removeKeyServer(server2.address))
      .then(() => setContract.startMigration(migrationId, {from: server1.address}))
      .then(() => setContract.getMigrationKeyServerPublic(server3.address))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should return address from migration set", () => Promise
      .resolve(defaultInitializationWithRealAccounts(setContract))
      .then(c => c.removeKeyServer(server2.address))
      .then(() => setContract.startMigration(migrationId, {from: server1.address}))
      .then(() => setContract.getMigrationKeyServerAddress(server1.address))
      .then(p => assert.equal(server1.ip, p))
    );

    it("should not return address from server not on migration set", () => Promise
      .resolve(defaultInitializationWithRealAccounts(setContract))
      .then(c => c.removeKeyServer(server2.address))
      .then(() => setContract.startMigration(migrationId, {from: server1.address}))
      .then(() => setContract.getMigrationKeyServerAddress(server3.address))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should return public from new set", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.getNewKeyServerPublic(server1.address))
      .then(p => assert.equal(server1.public, p))
    );

    it("should not return public from server not on new set", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.getNewKeyServerPublic(server3.address))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should return address from new set", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.getNewKeyServerAddress(server1.address))
      .then(p => assert.equal(server1.ip, p))
    );

    it("should not return address from server not on new set", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.getNewKeyServerAddress(server3.address))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should not allow to initialize twice", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.completeInitialization())
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should not allow to initialize by non-owner", () => Promise
      .try(() => setContract.completeInitialization({from: nonOwner}))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should return current key servers after initialization", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.getCurrentKeyServers())
      .then((servers) => {
        assert(servers.includes(server1.address));
        assert(servers.includes(server2.address));
        assert(!servers.includes(server3.address));
      })
    );

    it("should not return migration key servers after initialization", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.getMigrationKeyServers())
      .then((servers) => {
        assert(servers.length == 0);
      })
    );

    it("should return new key servers after initialization", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.getNewKeyServers())
      .then((servers) => {
        assert(servers.includes(server1.address));
        assert(servers.includes(server2.address));
        assert(!servers.includes(server3.address));
      })
    );

    it("should accept addKeyServer from owner", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.addKeyServer(server3.public, server3.ip))
      // not yet on current set
      .then(() => setContract.getCurrentKeyServers())
      .then((servers) => {
        assert(servers.includes(server1.address));
        assert(servers.includes(server2.address));
        assert(!servers.includes(server3.address));
      })
      // not yet on migration set
      .then(() => setContract.getMigrationKeyServers())
      .then((servers) => {
        assert(!servers.includes(server1.address));
        assert(!servers.includes(server2.address));
        assert(!servers.includes(server3.address));
      })
      // on new set
      .then(() => setContract.getNewKeyServers())
      .then((servers) => {
        assert(servers.includes(server1.address));
        assert(servers.includes(server2.address));
        assert(servers.includes(server3.address));
      })
    );

    it("should not accept addKeyServer from non-owner", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.addKeyServer(server3.public, server3.ip, {from: nonOwner}))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should not accept invalid public in addKeyServer", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.addKeyServer(invalidPublic, server3.ip))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should not accept existing public in addKeyServer", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.addKeyServer(server2.public, server2.ip))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should accept removeKeyServer from owner", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.removeKeyServer(server2.address))
      // not yet on current set
      .then(() => setContract.getCurrentKeyServers())
      .then((servers) => {
        assert(servers.includes(server1.address));
        assert(servers.includes(server2.address));
        assert(!servers.includes(server3.address));
      })
      // not yet on migration set
      .then(() => setContract.getMigrationKeyServers())
      .then((servers) => {
        assert(!servers.includes(server1.address));
        assert(!servers.includes(server2.address));
        assert(!servers.includes(server3.address));
      })
      // on new set
      .then(() => setContract.getNewKeyServers())
      .then((servers) => {
        assert(servers.includes(server1.address));
        assert(!servers.includes(server2.address));
        assert(!servers.includes(server3.address));
      })
    );

    it("should not accept removeKeyServer from non-owner", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.removeKeyServer(server2.address, {from: nonOwner}))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should not accept non-existing public in removeKeyServer", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.removeKeyServer(server3.address))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should not return migration id when migration is inactive", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.getMigrationId())
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should start migration", () => Promise
      .resolve(defaultInitializationWithRealAccounts(setContract))
      .then(c => c.addKeyServer(server3.public, server3.ip))
      .then(() => setContract.startMigration(migrationId, {from: server1.address}))
      // check migration id
      .then(() => setContract.getMigrationId())
      .then(mid => assert.equal(migrationId, mid))
      // check migration master
      .then(() => setContract.getMigrationMaster())
      .then(mm => assert.equal(server1.address, mm))
      // not yet on current set
      .then(() => setContract.getCurrentKeyServers())
      .then((servers) => {
        assert(servers.includes(server1.address));
        assert(servers.includes(server2.address));
        assert(!servers.includes(server3.address));
      })
      // on migration set
      .then(() => setContract.getMigrationKeyServers())
      .then((servers) => {
        assert(servers.includes(server1.address));
        assert(servers.includes(server2.address));
        assert(servers.includes(server3.address));
      })
      // on new set
      .then(() => setContract.getNewKeyServers())
      .then((servers) => {
        assert(servers.includes(server1.address));
        assert(servers.includes(server2.address));
        assert(servers.includes(server3.address));
      })
    );

    it("should not start migration when another migration is in progress", () => Promise
      .resolve(defaultInitializationWithRealAccounts(setContract))
      .then(c => c.addKeyServer(server3.public, server3.ip))
      .then(() => setContract.startMigration(migrationId, {from: server1.address}))
      .then(() => setContract.startMigration(migrationId, {from: server1.address}))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should not start migration with invalid migration id", () => Promise
      .resolve(defaultInitializationWithRealAccounts(setContract))
      .then(c => c.addKeyServer(server3.public, server3.ip))
      .then(() => setContract.startMigration(invalidMigrationId, {from: server1.address}))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should not start migration when migration is not required", () => Promise
      .resolve(defaultInitializationWithRealAccounts(setContract))
      .then(() => setContract.startMigration(migrationId, {from: server1.address}))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should not start migration when called by unrelated key server", () => Promise
      .resolve(defaultInitializationWithRealAccounts(setContract))
      .then(c => c.addKeyServer(server3.public, server3.ip))
      .then(() => setContract.startMigration(migrationId, {from: nonKeyServer}))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should accept confirmMigration", () => Promise
      .resolve(defaultInitializationWithRealAccounts(setContract))
      .then(c => c.addKeyServer(server3.public, server3.ip))
      .then(() => setContract.startMigration(migrationId, {from: server1.address}))
      // check that migration is not confirmed by any node
      .then(() => setContract.isMigrationConfirmed(server1.address))
      .then(isConfirmed => assert(!isConfirmed))
      .then(() => setContract.isMigrationConfirmed(server2.address))
      .then(isConfirmed => assert(!isConfirmed))
      .then(() => setContract.isMigrationConfirmed(server3.address))
      .then(isConfirmed => assert(!isConfirmed))
      // confirm by server1
      .then(() => setContract.confirmMigration(migrationId, {from: server1.address}))
      // check that migration confirmed by server1 only
      .then(() => setContract.isMigrationConfirmed(server1.address))
      .then(isConfirmed => assert(isConfirmed))
      .then(() => setContract.isMigrationConfirmed(server2.address))
      .then(isConfirmed => assert(!isConfirmed))
      .then(() => setContract.isMigrationConfirmed(server3.address))
      .then(isConfirmed => assert(!isConfirmed))
      // confirm by server2
      .then(() => setContract.confirmMigration(migrationId, {from: server2.address}))
      // check that migration confirmed by server1+server2 only
      .then(() => setContract.isMigrationConfirmed(server1.address))
      .then(isConfirmed => assert(isConfirmed))
      .then(() => setContract.isMigrationConfirmed(server2.address))
      .then(isConfirmed => assert(isConfirmed))
      .then(() => setContract.isMigrationConfirmed(server3.address))
      .then(isConfirmed => assert(!isConfirmed))
      // confirm by server3
      .then(() => setContract.confirmMigration(migrationId, {from: server3.address}))
      // on current set
      .then(() => setContract.getCurrentKeyServers())
      .then((servers) => {
        assert(servers.includes(server1.address));
        assert(servers.includes(server2.address));
        assert(servers.includes(server3.address));
      })
      // on migration set
      .then(() => setContract.getMigrationKeyServers())
      .then((servers) => {
        assert(!servers.includes(server1.address));
        assert(!servers.includes(server2.address));
        assert(!servers.includes(server3.address));
      })
      // on new set
      .then(() => setContract.getNewKeyServers())
      .then((servers) => {
        assert(servers.includes(server1.address));
        assert(servers.includes(server2.address));
        assert(servers.includes(server3.address));
      })
    );

    it("should not accept wrong migrationId in confirmMigration", () => Promise
      .resolve(defaultInitializationWithRealAccounts(setContract))
      .then(c => c.addKeyServer(server3.public, server3.ip))
      .then(() => setContract.startMigration(migrationId, {from: server1.address}))
      .then(() => setContract.confirmMigration(otherMigrationId, {from: server1.address}))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should fail when checking for migration confirmation from non-participant", () => Promise
      .resolve(defaultInitialization(setContract))
      .then(c => c.isMigrationConfirmed(server3.address))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should fail when trying to migrate to empty set", () => Promise
      .resolve(defaultInitializationWithRealAccounts(setContract))
      .then(() => setContract.removeKeyServer(server1.address))
      .then(() => setContract.removeKeyServer(server2.address))
      .then(() => setContract.startMigration(migrationId, {from: server1.address}))
      .then(() => assert(false, "supposed to fail"), () => {})
    );

    it("should fail when trying to confirm migration twice", () => Promise
      .resolve(defaultInitializationWithRealAccounts(setContract))
      .then(c => c.addKeyServer(server3.public, server3.ip))
      .then(() => setContract.startMigration(migrationId, {from: server1.address}))
      .then(() => setContract.confirmMigration(migrationId, {from: server1.address}))
      .then(() => setContract.confirmMigration(migrationId, {from: server1.address}))
      .then(() => assert(false, "supposed to fail"), () => {})
    );
  });
});
