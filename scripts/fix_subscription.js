/**
 * Mevcut şirket ve kullanıcının abonelik verilerini Firestore'da ayarlar.
 * Firebase CLI token'ını kullanarak Firestore REST API ile iletişim kurar.
 * 
 * Kullanım: node scripts/fix_subscription.js
 */

const fs = require('fs');
const https = require('https');
const path = require('path');

const PROJECT_ID = 'insaat-yonetim-takip';

// Firebase CLI'dan token al
function getFirebaseToken() {
  const configPath = path.join(
    process.env.USERPROFILE || process.env.HOME,
    '.config', 'configstore', 'firebase-tools.json'
  );
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  return config.tokens?.refresh_token || null;
}

async function refreshAccessToken(refreshToken) {
  // Firebase CLI uses its own client ID
  const clientId = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
  const clientSecret = 'j9iVZfS8kkCEFUPaAeJV0sAi';
  
  const postData = `client_id=${clientId}&client_secret=${clientSecret}&refresh_token=${refreshToken}&grant_type=refresh_token`;
  
  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'oauth2.googleapis.com',
      path: '/token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(postData),
      },
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

function firestoreRequest(method, path, accessToken, body) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'firestore.googleapis.com',
      path: `/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}`,
      method,
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
    };
    
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch {
          reject(new Error(data));
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

function parseFirestoreValue(val) {
  if (!val) return null;
  if (val.stringValue !== undefined) return val.stringValue;
  if (val.integerValue !== undefined) return parseInt(val.integerValue);
  if (val.booleanValue !== undefined) return val.booleanValue;
  if (val.timestampValue !== undefined) return new Date(val.timestampValue);
  if (val.mapValue !== undefined) {
    const result = {};
    const fields = val.mapValue.fields || {};
    for (const [k, v] of Object.entries(fields)) {
      result[k] = parseFirestoreValue(v);
    }
    return result;
  }
  if (val.arrayValue !== undefined) return (val.arrayValue.values || []).map(parseFirestoreValue);
  return null;
}

async function main() {
  console.log('Firebase token alınıyor...');
  const refreshToken = getFirebaseToken();
  if (!refreshToken) {
    console.error('Firebase CLI token bulunamadı. `npx firebase-tools login` yapın.');
    return;
  }
  
  const accessToken = await refreshAccessToken(refreshToken);
  console.log('Token alındı ✅\n');
  
  // Şirketleri listele
  console.log('Şirketler okunuyor...');
  const sirketlerResult = await firestoreRequest('GET', 'sirketler', accessToken);
  
  if (!sirketlerResult.documents || sirketlerResult.documents.length === 0) {
    console.log('Hiç şirket bulunamadı!');
    return;
  }
  
  const oneYearFromNow = new Date();
  oneYearFromNow.setFullYear(oneYearFromNow.getFullYear() + 1);
  
  for (const doc of sirketlerResult.documents) {
    const docPath = doc.name.split('/documents/')[1];
    const docId = docPath.split('/').pop();
    const fields = doc.fields || {};
    
    const ad = parseFirestoreValue(fields.ad) || '(N/A)';
    const yonetici = parseFirestoreValue(fields.yoneticiEposta) || '(N/A)';
    const subEnd = parseFirestoreValue(fields.subscriptionEndDate);
    const subType = parseFirestoreValue(fields.subscriptionType);
    const isActive = subEnd ? subEnd > new Date() : false;
    const adminlar = parseFirestoreValue(fields.adminlar) || {};
    
    console.log(`\nŞirket: ${ad}`);
    console.log(`  ID: ${docId}`);
    console.log(`  Yönetici: ${yonetici}`);
    console.log(`  Abonelik: ${subType || '(yok)'} — Bitiş: ${subEnd ? subEnd.toISOString() : '(yok)'} — Aktif: ${isActive}`);
    console.log(`  Adminlar: ${Object.keys(adminlar).join(', ') || '(yok)'}`);
    
    if (!isActive) {
      console.log(`  >>> Güncelleniyor...`);
      
      // Şirket dokümanını güncelle (PATCH)
      const updateBody = {
        fields: {
          ...fields,
          subscriptionType: { stringValue: 'yearly' },
          subscriptionEndDate: { timestampValue: oneYearFromNow.toISOString() },
          autoRenew: { booleanValue: true },
        },
      };
      
      await firestoreRequest('PATCH', `sirketler/${docId}`, accessToken, updateBody);
      console.log(`  ✅ Şirket aboneliği ${oneYearFromNow.toISOString()} tarihine uzatıldı.`);
      
      // Admin kullanıcılarını güncelle
      for (const uid of Object.keys(adminlar)) {
        console.log(`  Kullanıcı ${uid} güncelleniyor...`);
        
        // Önce mevcut user doc'u oku
        let existingFields = {};
        try {
          const userDoc = await firestoreRequest('GET', `users/${uid}`, accessToken);
          existingFields = userDoc.fields || {};
        } catch {}
        
        const userBody = {
          fields: {
            ...existingFields,
            subscriptionType: { stringValue: 'yearly' },
            subscriptionEndDate: { timestampValue: oneYearFromNow.toISOString() },
            autoRenew: { booleanValue: true },
          },
        };
        
        await firestoreRequest('PATCH', `users/${uid}`, accessToken, userBody);
        console.log(`  ✅ Kullanıcı ${uid} aboneliği güncellendi.`);
      }
    } else {
      console.log(`  ✓ Zaten aktif`);
    }
  }
  
  console.log('\n✅ Tamamlandı!\n');
}

main().catch(console.error).finally(() => process.exit(0));
