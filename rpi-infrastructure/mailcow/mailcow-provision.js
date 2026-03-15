#!/usr/bin/env node
/**
 * mailcow-provision.js — Provisions email accounts for adscreen.az
 * 
 * Requires: MAILCOW_API_KEY and MAILCOW_HOST in .env
 * Run once after Mailcow is running: node mailcow-provision.js
 * 
 * Creates:
 *   - salim@adscreen.az, elturan@adscreen.az, teymur@adscreen.az (mailboxes)
 *   - info@adscreen.az → forwards to all three
 *   - support@adscreen.az (shared mailbox)
 */

import crypto from 'crypto';

const MAILCOW_HOST = process.env.MAILCOW_HOST || 'https://mail.adscreen.az';
const MAILCOW_API_KEY = process.env.MAILCOW_API_KEY;

if (!MAILCOW_API_KEY) {
    console.error('❌ Set MAILCOW_API_KEY in your environment before running.');
    process.exit(1);
}

const headers = {
    'Content-Type': 'application/json',
    'X-API-Key': MAILCOW_API_KEY,
};

async function api(endpoint, body) {
    const url = `${MAILCOW_HOST}/api/v1/${endpoint}`;
    const res = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
    const json = await res.json().catch(() => ({}));
    if (!res.ok && res.status !== 200) {
        console.warn(`⚠️  ${endpoint}: HTTP ${res.status}`, JSON.stringify(json));
    }
    return json;
}

function generatePassword(length = 20) {
    return crypto.randomBytes(length).toString('base64url').slice(0, length);
}

async function provision() {
    console.log('🔧 Provisioning adscreen.az mail accounts...\n');

    // ── 1. Add Domain ──
    console.log('📁 Adding domain adscreen.az...');
    await api('add/domain', {
        domain: 'adscreen.az',
        description: 'Adscreen Digital Signage',
        aliases: 100,
        mailboxes: 50,
        maxquota: 5120,    // 5GB per mailbox
        defquota: 2048,    // 2GB default
        active: 1,
    });

    // ── 2. Create Mailboxes ──
    const accounts = [
        { local_part: 'salim',   name: 'Salim Aghasalim' },
        { local_part: 'elturan', name: 'Elturan' },
        { local_part: 'teymur',  name: 'Teymur' },
        { local_part: 'support', name: 'Support (Shared)' },
    ];

    const credentials = [];

    for (const acct of accounts) {
        const password = generatePassword();
        console.log(`📬 Creating ${acct.local_part}@adscreen.az ...`);
        const result = await api('add/mailbox', {
            local_part: acct.local_part,
            domain: 'adscreen.az',
            name: acct.name,
            password: password,
            password2: password,
            quota: 5120,  // 5GB
            active: 1,
        });
        credentials.push({
            email: `${acct.local_part}@adscreen.az`,
            password,
            imap: { host: 'mail.adscreen.az', port: 993, tls: true },
            smtp: { host: 'mail.adscreen.az', port: 587, starttls: true },
            result,
        });
    }

    // ── 3. Create Alias: info@ → forwards to all three ──
    console.log('📨 Creating info@adscreen.az alias → salim, elturan, teymur...');
    await api('add/alias', {
        address: 'info@adscreen.az',
        goto: 'salim@adscreen.az,elturan@adscreen.az,teymur@adscreen.az',
        active: 1,
    });

    // ── 4. Output Credentials ──
    console.log('\n' + '═'.repeat(60));
    console.log('  ✅ PROVISIONING COMPLETE — CREDENTIALS');
    console.log('═'.repeat(60));

    for (const c of credentials) {
        console.log(`\n  📧 ${c.email}`);
        console.log(`     Password: ${c.password}`);
        console.log(`     IMAP:     ${c.imap.host}:${c.imap.port} (TLS)`);
        console.log(`     SMTP:     ${c.smtp.host}:${c.smtp.port} (STARTTLS)`);
    }

    console.log(`\n  📨 info@adscreen.az → forwards to salim, elturan, teymur`);
    console.log(`  📨 support@adscreen.az → shared mailbox (login directly)`);
    console.log('\n' + '═'.repeat(60));
    console.log('⚠️  SAVE THESE CREDENTIALS SECURELY — they are not stored.\n');
}

provision().catch(err => {
    console.error('🔥 Provisioning failed:', err);
    process.exit(1);
});
