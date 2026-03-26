/**
 * Belirli bir kullanıcı için yıllık abonelikli şirket hesabı oluşturur.
 * 
 * Kullanım: node scripts/create_company_for_user.js
 */

const fs = require('fs');
const https = require('https');
const path = require('path');

const PROJECT_ID = 'insaat-yonetim-takip';
const API_KEY = 'AIzaSyAFPmbGYzuFhropyLDn3iidaRlzgVX_hpo'; // Web API key

// ======= AYARLAR =======
const TARGET_EMAIL = 'adnancolpa@icloud.com';
const COMPANY_NAME = 'Adnan Colpa';
const SUBSCRIPTION_TYPE = 'yearly';
const SUBSCRIPTION_DAYS = 365;
// ========================

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

function identityRequest(action, body) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify(body);
    const options = {
      hostname: 'identitytoolkit.googleapis.com',
      path: `/v1/accounts:${action}?key=${API_KEY}`,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) },
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

// Firebase Auth Admin REST API - kullanıcıyı email ile bul
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

async function main() {
  try {
    console.log(`\n🔧 Şirket oluşturma: ${TARGET_EMAIL}\n`);
    
    // 1. Firebase token al
    const refreshToken = getFirebaseToken();
    if (!refreshToken) { console.error('❌ Firebase CLI token bulunamadı. "firebase login" yapın.'); return; }
    
    const accessToken = await refreshAccessToken(refreshToken);
    console.log('✅ Token alındı');
    
    // 2. Kullanıcıyı Firebase Auth'ta bul
    console.log(`🔍 Kullanıcı aranıyor: ${TARGET_EMAIL}`);
    const lookupResult = await lookupUserByEmail(accessToken, TARGET_EMAIL);
    
    let userId;
    if (lookupResult.users && lookupResult.users.length > 0) {
      userId = lookupResult.users[0].localId;
      console.log(`✅ Kullanıcı bulundu: UID = ${userId}`);
    } else {
      console.log(`⚠️  Kullanıcı Auth'ta bulunamadı. Henüz giriş yapmamış olabilir.`);
      console.log(`   Şirket yine de oluşturulacak, kullanıcı ilk girişte bağlanacak.`);
      userId = 'pending_' + Date.now();
    }
    
    // 3. Bu email ile zaten şirket var mı kontrol et
    console.log('🔍 Mevcut şirketler kontrol ediliyor...');
    const sirketlerResult = await firestoreRequest('GET', 'sirketler', accessToken);
    
    if (sirketlerResult.documents) {
      for (const doc of sirketlerResult.documents) {
        const fields = doc.fields || {};
        const emailler = fields.emailler?.arrayValue?.values?.map(v => v.stringValue) || [];
        const yoneticiEposta = fields.yoneticiEposta?.stringValue || '';
        
        if (emailler.includes(TARGET_EMAIL.toLowerCase()) || yoneticiEposta.toLowerCase() === TARGET_EMAIL.toLowerCase()) {
          const docId = doc.name.split('/').pop();
          console.log(`⚠️  Bu email zaten "${fields.ad?.stringValue}" şirketinde kayıtlı (ID: ${docId})`);
          console.log(`   Mevcut şirketin aboneliği güncellenecek...`);
          
          // Abonelik güncelle
          const endDate = new Date();
          endDate.setDate(endDate.getDate() + SUBSCRIPTION_DAYS);
          
          const updatedFields = { ...fields };
          updatedFields.subscriptionType = { stringValue: SUBSCRIPTION_TYPE };
          updatedFields.subscriptionEndDate = { timestampValue: endDate.toISOString() };
          updatedFields.autoRenew = { booleanValue: true };
          updatedFields.aktif = { booleanValue: true };
          updatedFields.odemePaid = { booleanValue: true };
          updatedFields.odemeDate = { timestampValue: new Date().toISOString() };
          updatedFields.odemeTransactionId = { stringValue: 'manual_admin_' + Date.now() };
          
          const updateResult = await firestoreRequest('PATCH', `sirketler/${docId}`, accessToken, { fields: updatedFields });
          
          if (updateResult.name) {
            console.log(`\n✅ Abonelik güncellendi!`);
            console.log(`   Şirket: ${fields.ad?.stringValue}`);
            console.log(`   Tip: ${SUBSCRIPTION_TYPE}`);
            console.log(`   Bitiş: ${endDate.toLocaleDateString('tr-TR')}`);
          } else {
            console.log(`❌ Güncelleme başarısız:`, JSON.stringify(updateResult, null, 2));
          }
          
          // Users koleksiyonunu da güncelle
          if (userId && !userId.startsWith('pending_')) {
            const userFields = {
              sirketId: { stringValue: docId },
              companyCreationPaid: { booleanValue: true },
              subscriptionType: { stringValue: SUBSCRIPTION_TYPE },
              subscriptionEndDate: { timestampValue: endDate.toISOString() },
              autoRenew: { booleanValue: true },
              lastPurchaseStatus: { stringValue: 'purchased' },
            };
            await firestoreRequest('PATCH', `users/${userId}`, accessToken, { fields: userFields });
            console.log(`✅ Users koleksiyonu güncellendi (UID: ${userId})`);
          }
          
          return;
        }
      }
    }
    
    // 4. Yeni şirket oluştur
    console.log('📦 Yeni şirket oluşturuluyor...');
    
    const endDate = new Date();
    endDate.setDate(endDate.getDate() + SUBSCRIPTION_DAYS);
    
    const normalizedEmail = TARGET_EMAIL.trim().toLowerCase();
    
    const companyFields = {
      ad: { stringValue: COMPANY_NAME },
      yoneticiEposta: { stringValue: normalizedEmail },
      yoneticiIletisimEposta: { stringValue: normalizedEmail },
      telefon: { stringValue: '' },
      adres: { stringValue: '' },
      aktif: { booleanValue: true },
      personelListesi: { arrayValue: { values: [] } },
      emailler: { 
        arrayValue: { 
          values: [{ stringValue: normalizedEmail }] 
        } 
      },
      adminlar: userId && !userId.startsWith('pending_') 
        ? { mapValue: { fields: { [userId]: { booleanValue: true } } } }
        : { mapValue: { fields: {} } },
      olusturmaTarihi: { timestampValue: new Date().toISOString() },
      subscriptionType: { stringValue: SUBSCRIPTION_TYPE },
      subscriptionEndDate: { timestampValue: endDate.toISOString() },
      autoRenew: { booleanValue: true },
      odemePaid: { booleanValue: true },
      odemeDate: { timestampValue: new Date().toISOString() },
      odemeTransactionId: { stringValue: 'manual_admin_' + Date.now() },
    };
    
    const createResult = await firestoreRequest('POST', 'sirketler', accessToken, { fields: companyFields });
    
    if (createResult.name) {
      const newDocId = createResult.name.split('/').pop();
      console.log(`\n✅ Şirket başarıyla oluşturuldu!`);
      console.log(`   ID: ${newDocId}`);
      console.log(`   Ad: ${COMPANY_NAME}`);
      console.log(`   Email: ${normalizedEmail}`);
      console.log(`   Abonelik: ${SUBSCRIPTION_TYPE}`);
      console.log(`   Bitiş: ${endDate.toLocaleDateString('tr-TR')}`);
      
      // Users koleksiyonunu güncelle
      if (userId && !userId.startsWith('pending_')) {
        const userFields = {
          sirketId: { stringValue: newDocId },
          companyCreationPaid: { booleanValue: true },
          subscriptionType: { stringValue: SUBSCRIPTION_TYPE },
          subscriptionEndDate: { timestampValue: endDate.toISOString() },
          autoRenew: { booleanValue: true },
          lastPurchaseStatus: { stringValue: 'purchased' },
        };
        await firestoreRequest('PATCH', `users/${userId}`, accessToken, { fields: userFields });
        console.log(`✅ Users koleksiyonu güncellendi (UID: ${userId})`);
      }
    } else {
      console.log('❌ Şirket oluşturulamadı:', JSON.stringify(createResult, null, 2));
    }
    
  } catch (error) {
    console.error('❌ Hata:', error.message);
  }
}

main();
