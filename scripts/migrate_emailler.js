"/**
 * Mevcut şirketlere 'emailler' array field ekler.
 * yoneticiEposta + personelListesi'ndeki tüm emailleri toplar.
 * 
 * Kullanım: node scripts/migrate_emailler.js
 */

const fs = require('fs');
const https = require('https');
const path = require('path');

const PROJECT_ID = 'insaat-yonetim-takip';

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

async function main() {
  const refreshToken = getFirebaseToken();
  if (!refreshToken) { console.error('Firebase CLI token bulunamadı.'); return; }
  
  const accessToken = await refreshAccessToken(refreshToken);
  console.log('Token alındı ✅\n');
  
  const sirketlerResult = await firestoreRequest('GET', 'sirketler', accessToken);
  if (!sirketlerResult.documents || sirketlerResult.documents.length === 0) {
    console.log('Hiç şirket bulunamadı!');
    return;
  }
  
  for (const doc of sirketlerResult.documents) {
    const docId = doc.name.split('/').pop();
    const fields = doc.fields || {};
    
    // Zaten emailler varsa atla
    if (fields.emailler && fields.emailler.arrayValue && fields.emailler.arrayValue.values) {
      console.log(`${fields.ad?.stringValue || docId}: emailler zaten var (${fields.emailler.arrayValue.values.length} adet)`);
      continue;
    }
    
    const emails = new Set();
    
    // yoneticiEposta
    if (fields.yoneticiEposta?.stringValue) {
      emails.add(fields.yoneticiEposta.stringValue.trim().toLowerCase());
    }
    
    // personelListesi
    if (fields.personelListesi?.arrayValue?.values) {
      for (const p of fields.personelListesi.arrayValue.values) {
        const pFields = p.mapValue?.fields;
        if (pFields?.email?.stringValue) {
          emails.add(pFields.email.stringValue.trim().toLowerCase());
        }
      }
    }
    
    const emailArray = [...emails].filter(e => e.length > 0);
    console.log(`${fields.ad?.stringValue || docId}: ${emailArray.length} email bulundu → ${emailArray.join(', ')}`);
    
    // Güncelle
    const updateBody = {
      fields: {
        ...fields,
        emailler: {
          arrayValue: {
            values: emailArray.map(e => ({ stringValue: e }))
          }
        }
      }
    };
    
    await firestoreRequest('PATCH', `sirketler/${docId}`, accessToken, updateBody);
    console.log(`  ✅ emailler array eklendi`);
  }
  
  console.log('\n✅ Migration tamamlandı!');
}

main().catch(console.error).finally(() => process.exit(0));
