/**
 * Şirket ve kullanıcı durumunu kontrol eder.
 * Kullanım: node scripts/check_user_company.js
 */

const fs = require('fs');
const https = require('https');
const path = require('path');

const PROJECT_ID = 'insaat-yonetim-takip';
const TARGET_EMAIL = 'adnancolpa@icloud.com';

function getFirebaseToken() {
  const configPath = path.join(
    process.env.USERPROFILE || process.env.HOME,
    '.config', 'configstore', 'firebase-tools.json'
  );
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  return config.tokens?.refresh_token || null;
}

async function refreshAccessToken(refreshToken) {
  const clientId = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
  const clientSecret = 'j9iVZfS8kkCEFUPaAeJV0sAi';
  const postData = `client_id=${clientId}&client_secret=${clientSecret}&refresh_token=${refreshToken}&grant_type=refresh_token`;
  
  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'oauth2.googleapis.com',
      path: '/token',
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(postData) },
    }, (res) => {
      let body = '';
      res.on('data', d => body += d);
      res.on('end', () => {
        const result = JSON.parse(body);
        if (result.access_token) resolve(result.access_token);
        else reject(new Error('Token refresh failed: ' + body));
      });
    });
    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

function firestoreRequest(method, docPath, accessToken, body) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'firestore.googleapis.com',
      path: `/v1/projects/${PROJECT_ID}/databases/(default)/documents/${docPath}`,
      method,
      headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => { try { resolve(JSON.parse(data)); } catch { reject(new Error(data)); } });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

function lookupUserByEmail(accessToken, email) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify({ email: [email] });
    const options = {
      hostname: 'identitytoolkit.googleapis.com',
      path: `/v1/projects/${PROJECT_ID}/accounts:lookup`,
      method: 'POST',
      headers: { 
        'Authorization': `Bearer ${accessToken}`, 
        'Content-Type': 'application/json', 
        'Content-Length': Buffer.byteLength(postData) 
      },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => { try { resolve(JSON.parse(data)); } catch { reject(new Error(data)); } });
    });
    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

// Structured query for sirketler by emailler array
function runQuery(accessToken, email) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: 'sirketler' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'emailler' },
            op: 'ARRAY_CONTAINS',
            value: { stringValue: email }
          }
        }
      }
    });
    const options = {
      hostname: 'firestore.googleapis.com',
      path: `/v1/projects/${PROJECT_ID}/databases/(default)/documents:runQuery`,
      method: 'POST',
      headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => { try { resolve(JSON.parse(data)); } catch { reject(new Error(data)); } });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function main() {
  try {
    const refreshToken = getFirebaseToken();
    const accessToken = await refreshAccessToken(refreshToken);
    console.log('✅ Token alındı\n');
    
    // 1. Firebase Auth kontrol
    console.log('=== FIREBASE AUTH ===');
    const lookup = await lookupUserByEmail(accessToken, TARGET_EMAIL);
    if (lookup.users && lookup.users.length > 0) {
      const user = lookup.users[0];
      console.log(`UID: ${user.localId}`);
      console.log(`Email: ${user.email}`);
      console.log(`Created: ${new Date(parseInt(user.createdAt)).toLocaleString('tr-TR')}`);
      console.log(`Last Login: ${new Date(parseInt(user.lastLoginAt)).toLocaleString('tr-TR')}`);
      
      // 2. Users koleksiyonu kontrol
      console.log('\n=== USERS COLLECTION ===');
      const userDoc = await firestoreRequest('GET', `users/${user.localId}`, accessToken);
      if (userDoc.fields) {
        console.log('Belge bulundu:');
        for (const [key, val] of Object.entries(userDoc.fields)) {
          const value = val.stringValue || val.booleanValue || val.timestampValue || val.integerValue || JSON.stringify(val);
          console.log(`  ${key}: ${value}`);
        }
      } else {
        console.log('❌ users/{uid} belgesi yok!');
      }
    } else {
      console.log(`❌ Kullanıcı Auth'ta bulunamadı: ${TARGET_EMAIL}`);
    }
    
    // 3. Şirket doğrudan ID ile kontrol
    console.log('\n=== SIRKET BY ID (7bMqWORYWNgeJ4Fe0XIC) ===');
    const directDoc = await firestoreRequest('GET', 'sirketler/7bMqWORYWNgeJ4Fe0XIC', accessToken);
    if (directDoc.fields) {
      console.log('Şirket bulundu:');
      for (const [key, val] of Object.entries(directDoc.fields)) {
        if (key === 'personelListesi' || key === 'adminlar') {
          console.log(`  ${key}: ${JSON.stringify(val)}`);
        } else {
          const value = val.stringValue || val.booleanValue || val.timestampValue || val.integerValue || JSON.stringify(val);
          console.log(`  ${key}: ${value}`);
        }
      }
    } else {
      console.log('❌ Şirket bulunamadı:', JSON.stringify(directDoc));
    }
    
    // 4. Email araması (uygulama gibi)
    console.log('\n=== EMAIL QUERY (arrayContains) ===');
    const queryResult = await runQuery(accessToken, TARGET_EMAIL.toLowerCase());
    if (Array.isArray(queryResult)) {
      const docs = queryResult.filter(r => r.document);
      console.log(`${docs.length} şirket bulundu`);
      for (const r of docs) {
        const docId = r.document.name.split('/').pop();
        const ad = r.document.fields?.ad?.stringValue;
        const yoneticiEposta = r.document.fields?.yoneticiEposta?.stringValue;
        console.log(`  - ${ad} (${docId}) yonetici: ${yoneticiEposta}`);
      }
    } else {
      console.log('Query sonucu:', JSON.stringify(queryResult, null, 2));
    }
    
  } catch (error) {
    console.error('❌ Hata:', error.message);
  }
}

main();
