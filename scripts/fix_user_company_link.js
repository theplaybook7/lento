/**
 * Kullanıcı-şirket bağlantısını düzeltir.
 * users/{uid} doc oluşturur ve adminlar'a UID ekler.
 * 
 * Kullanım: node scripts/fix_user_company_link.js
 */

const fs = require('fs');
const https = require('https');
const path = require('path');

const PROJECT_ID = 'insaat-yonetim-takip';

const USER_UID = '10DceyBhF8guyHzuLsmBCSxo9ID3';
const COMPANY_ID = '7bMqWORYWNgeJ4Fe0XIC';

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
  try {
    const refreshToken = getFirebaseToken();
    const accessToken = await refreshAccessToken(refreshToken);
    console.log('✅ Token alındı\n');

    // 1. users/{uid} belgesi oluştur
    console.log('📝 users/{uid} belgesi oluşturuluyor...');
    const userFields = {
      sirketId: { stringValue: COMPANY_ID },
      companyCreationPaid: { booleanValue: true },
      subscriptionType: { stringValue: 'yearly' },
      subscriptionEndDate: { timestampValue: '2027-03-26T16:30:08.949Z' },
      autoRenew: { booleanValue: true },
      lastPurchaseStatus: { stringValue: 'purchased' },
    };
    
    const userResult = await firestoreRequest('PATCH', `users/${USER_UID}`, accessToken, { fields: userFields });
    if (userResult.name) {
      console.log(`✅ users/${USER_UID} belgesi oluşturuldu`);
      console.log(`   sirketId: ${COMPANY_ID}`);
    } else {
      console.log('❌ Users belgesi oluşturulamadı:', JSON.stringify(userResult));
    }

    // 2. Şirketin adminlar map'ine UID ekle
    console.log('\n📝 adminlar güncelleniyor...');
    const sirketDoc = await firestoreRequest('GET', `sirketler/${COMPANY_ID}`, accessToken);
    
    if (sirketDoc.fields) {
      const updatedFields = { ...sirketDoc.fields };
      updatedFields.adminlar = {
        mapValue: {
          fields: {
            [USER_UID]: { booleanValue: true }
          }
        }
      };
      
      const updateResult = await firestoreRequest('PATCH', `sirketler/${COMPANY_ID}`, accessToken, { fields: updatedFields });
      if (updateResult.name) {
        console.log(`✅ adminlar güncellendi: ${USER_UID} → true`);
      } else {
        console.log('❌ Güncelleme başarısız:', JSON.stringify(updateResult));
      }
    }

    console.log('\n🎉 Tamamlandı! Kullanıcı artık giriş yapabilmeli.');
    
  } catch (error) {
    console.error('❌ Hata:', error.message);
  }
}

main();
