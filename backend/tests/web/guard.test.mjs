import assert from 'node:assert/strict';
import {test} from 'node:test';
import {Guard, fresh} from '../../src/navcore/web/guard.js';
const instruction={id:'one',capture_monotonic_ms:100,valid_for_ms:500};
test('capture age and receipt lifetime are independent strict bounds',()=>{
 assert.equal(fresh(instruction,200,699),true);
 assert.equal(fresh(instruction,200,700),false);
 assert.equal(fresh({...instruction,valid_for_ms:1000},1000,1100),false);
 assert.equal(fresh(instruction,200,99),false);
 assert.equal(fresh({...instruction,valid_for_ms:NaN},200,300),false);
});
test('only matching fresh results reset watchdog; heartbeat cannot reset it',()=>{
 const guard=new Guard(0);
 assert.equal(guard.outcome({capture_monotonic_ms:100},{at:99,requested:90},200),false);
 assert.equal(guard.outcome({capture_monotonic_ms:100},{at:100,requested:90},1100),false);
 assert.equal(guard.expired(1500),true);
 assert.equal(guard.expired(1600),false);
 assert.equal(guard.outcome({capture_monotonic_ms:1700},{at:1700,requested:1690},1800),true);
 assert.equal(guard.expired(3299),false);
 assert.equal(guard.expired(3300),true);
});
test('duplicate and manual repeat cannot extend original earliest deadline',()=>{
 const guard=new Guard(0);
 assert.equal(guard.instruction(instruction,200,250),700);
 assert.equal(guard.instruction(instruction,300,350),null);
 assert.equal(guard.instruction(instruction,300,350,true),700);
 assert.equal(guard.instruction(instruction,500,700,true),null);
});
