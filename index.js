const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const cors = require('cors');
const multer = require('multer');
const path = require('path');
const sqlite3 = require('sqlite3');
const { open } = require('sqlite');
const https = require('https');
const querystring = require('querystring');
const bcrypt = require('bcrypt');
const fs = require('fs');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

const JWT_SECRET = 'super_secret_key_123';
const PORT = 3000;

// Убедимся, что папка для загрузок существует
const uploadDir = 'uploads/';
if (!fs.existsSync(uploadDir)){
    fs.mkdirSync(uploadDir);
}

// API ключ от SMS.ru
const SMS_RU_API_ID = 'A401C694-6F0C-7405-B0EE-41E78BF0D0FB';

app.use(cors());
app.use(express.json());
app.use('/uploads', express.static('uploads'));

const storage = multer.diskStorage({
  destination: 'uploads/',
  filename: (req, file, cb) => {
    cb(null, Date.now() + path.extname(file.originalname));
  }
});
const upload = multer({ storage });

let db;
(async () => {
  db = await open({
    filename: './database.sqlite',
    driver: sqlite3.Database
  });

  await db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      phoneNumber TEXT UNIQUE,
      email TEXT UNIQUE,
      password TEXT,
      displayName TEXT,
      photoUrl TEXT,
      status TEXT,
      lastSeen INTEGER,
      fcmToken TEXT
    );
    CREATE TABLE IF NOT EXISTS chats (
      id TEXT PRIMARY KEY,
      participants TEXT,
      lastMessage TEXT,
      lastMessageTimestamp INTEGER,
      isGroup INTEGER DEFAULT 0,
      groupName TEXT,
      groupAdminId TEXT
    );
    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      chatId TEXT,
      senderId TEXT,
      text TEXT,
      type TEXT,
      mediaUrl TEXT,
      timestamp INTEGER,
      isRead INTEGER DEFAULT 0,
      replyToMessageId TEXT
    );
  `);

  // Миграция: добавляем колонки email и password если их нет
  try {
    await db.exec("ALTER TABLE users ADD COLUMN email TEXT UNIQUE");
  } catch (e) {}
  try {
    await db.exec("ALTER TABLE users ADD COLUMN password TEXT");
  } catch (e) {}
  // Миграция: добавляем колонку replyToMessageId в messages если её нет
  try {
    await db.exec("ALTER TABLE messages ADD COLUMN replyToMessageId TEXT");
  } catch (e) {}
})();

// API: Вход по почте и паролю
app.post('/api/auth/email-login', async (req, res) => {
  const { email, password } = req.body;
  
  if (!email || !password) {
    return res.status(400).json({ success: false, message: 'Email и пароль обязательны' });
  }
  
  // Нормализуем email: убираем пробелы и приводим к нижнему регистру
  const normalizedEmail = email.trim().toLowerCase();
  
  // Простая валидация формата email
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(normalizedEmail)) {
    return res.status(400).json({ success: false, message: 'Некорректный формат email. Проверьте правильность ввода.' });
  }
  
  try {
    // Ищем пользователя по email (без учета регистра)
    const user = await db.get('SELECT * FROM users WHERE LOWER(TRIM(email)) = ?', [normalizedEmail]);
    
    if (!user) {
      return res.status(400).json({ 
        success: false, 
        message: 'Пользователь с таким email не найден. Возможно, вы регистрировались по номеру телефона. Попробуйте войти через номер телефона или зарегистрируйтесь заново.' 
      });
    }
    
    if (!user.password) {
      return res.status(400).json({ 
        success: false, 
        message: 'Для этого аккаунта не установлен пароль. Вы регистрировались по номеру телефона. Войдите через номер телефона или восстановите пароль.' 
      });
    }

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(400).json({ success: false, message: 'Неверный пароль. Проверьте правильность ввода.' });
    }

    const token = jwt.sign({ id: user.id }, JWT_SECRET);
    res.json({ success: true, token, user });
  } catch (e) {
    console.error(`[ERROR] Login error: ${e.message}`);
    res.status(500).json({ success: false, message: 'Ошибка сервера. Попробуйте позже.' });
  }
});

// API: Регистрация по почте
app.post('/api/auth/email-register', async (req, res) => {
  const { email, password, displayName } = req.body;
  
  if (!email || !password) {
    return res.status(400).json({ success: false, message: 'Email и пароль обязательны' });
  }
  
  // Нормализуем email: убираем пробелы и приводим к нижнему регистру
  const normalizedEmail = email.trim().toLowerCase();
  
  // Простая валидация email
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(normalizedEmail)) {
    return res.status(400).json({ success: false, message: 'Некорректный формат email. Проверьте правильность ввода.' });
  }
  
  // Валидация пароля (минимум 6 символов)
  if (password.length < 6) {
    return res.status(400).json({ success: false, message: 'Пароль должен содержать минимум 6 символов' });
  }
  
  try {
    // Проверяем существование пользователя (без учета регистра)
    // Сначала проверяем прямой поиск по нормализованному email
    let existingUser = await db.get('SELECT * FROM users WHERE email = ?', [normalizedEmail]);
    
    // Если не нашли, проверяем все пользователи с email и сравниваем в коде
    if (!existingUser) {
      const allUsers = await db.all('SELECT * FROM users WHERE email IS NOT NULL');
      existingUser = allUsers.find(u => u.email && u.email.trim().toLowerCase() === normalizedEmail);
    }
    
    if (existingUser) {
      return res.status(400).json({ 
        success: false, 
        message: 'Пользователь с таким email уже зарегистрирован. Попробуйте войти или используйте другой email.' 
      });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    const id = Date.now().toString();
    const finalDisplayName = (displayName || normalizedEmail.split('@')[0]).trim();
    
    try {
      await db.run(
        'INSERT INTO users (id, email, password, displayName) VALUES (?, ?, ?, ?)',
        [id, normalizedEmail, hashedPassword, finalDisplayName]
      );
    } catch (dbError) {
      // Если ошибка связана с уникальностью email (может быть race condition)
      if (dbError.message && (dbError.message.includes('UNIQUE constraint') || dbError.message.includes('UNIQUE'))) {
        // Проверяем еще раз, может быть пользователь был создан между проверками
        const checkUser = await db.get('SELECT * FROM users WHERE email = ?', [normalizedEmail]);
        if (checkUser) {
          return res.status(400).json({ 
            success: false, 
            message: 'Пользователь с таким email уже зарегистрирован. Попробуйте войти.' 
          });
        }
        return res.status(400).json({ 
          success: false, 
          message: 'Ошибка при создании аккаунта. Попробуйте еще раз.' 
        });
      }
      throw dbError; // Пробрасываем другие ошибки дальше
    }

    // Получаем созданного пользователя для возврата
    const newUser = await db.get('SELECT id, email, displayName FROM users WHERE id = ?', [id]);
    if (!newUser) {
      return res.status(500).json({ 
        success: false, 
        message: 'Ошибка при создании пользователя. Попробуйте еще раз.' 
      });
    }

    const user = { 
      id: newUser.id, 
      email: newUser.email, 
      displayName: newUser.displayName 
    };
    const token = jwt.sign({ id: user.id }, JWT_SECRET);
    
    res.json({ success: true, token, user });
  } catch (e) {
    console.error(`[ERROR] Registration error for ${normalizedEmail}: ${e.message}`);
    console.error(`[ERROR] Stack: ${e.stack}`);
    res.status(500).json({ 
      success: false, 
      message: 'Ошибка сервера при регистрации. Попробуйте позже или обратитесь в поддержку.'
    });
  }
});

// Middleware для установки Content-Type для всех ответов
app.use((req, res, next) => {
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  next();
});

// Добавим middleware для HTTP запросов (определяем ДО использования)
const authMiddleware = (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) {
    return res.status(401).json({ success: false, error: 'No token' });
  }
  const token = authHeader.split(' ')[1];
  if (!token) {
    return res.status(401).json({ success: false, error: 'No token' });
  }
  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err) {
      return res.status(401).json({ success: false, error: 'Invalid token' });
    }
    req.userId = decoded.id;
    next();
  });
};

// API: Обновление токена FCM
app.post('/api/users/fcm-token', async (req, res) => {
  const { id, fcmToken } = req.body;
  await db.run('UPDATE users SET fcmToken = ? WHERE id = ?', [fcmToken, id]);
  res.json({ success: true });
});

// API: Создание группового чата
app.post('/api/chats/group', authMiddleware, async (req, res) => {
  const { participants, groupName, adminId } = req.body;
  const chatId = 'group_' + Date.now();
  try {
    await db.run(
      'INSERT INTO chats (id, participants, lastMessageTimestamp, isGroup, groupName, groupAdminId) VALUES (?, ?, ?, ?, ?, ?)',
      [chatId, JSON.stringify(participants), Date.now(), 1, groupName, adminId]
    );
    const chat = await db.get('SELECT * FROM chats WHERE id = ?', [chatId]);
    chat.participants = JSON.parse(chat.participants);
    
    // Уведомляем всех участников о создании группы
    participants.forEach(userId => {
      io.to(String(userId)).emit('chat_created', chat);
    });
    
    res.json(chat);
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// API: Добавление участника в группу
app.post('/api/chats/:chatId/add-participant', authMiddleware, async (req, res) => {
  const { chatId } = req.params;
  const { userId } = req.body;
  try {
    const chat = await db.get('SELECT * FROM chats WHERE id = ?', [chatId]);
    if (!chat || !chat.isGroup) {
      return res.status(404).json({ success: false, error: 'Группа не найдена' });
    }
    
    // Проверяем, что пользователь является администратором
    if (chat.groupAdminId !== req.userId) {
      return res.status(403).json({ success: false, error: 'Только администратор может добавлять участников' });
    }
    
    let participants = JSON.parse(chat.participants);
    if (!participants.includes(userId)) {
      participants.push(userId);
      await db.run(
        'UPDATE chats SET participants = ? WHERE id = ?',
        [JSON.stringify(participants), chatId]
      );
      
      // Уведомляем нового участника
      io.to(String(userId)).emit('chat_created', { ...chat, participants });
      
      res.json({ success: true, participants });
    } else {
      res.status(400).json({ success: false, error: 'Пользователь уже в группе' });
    }
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// API: Удаление участника из группы
app.post('/api/chats/:chatId/remove-participant', authMiddleware, async (req, res) => {
  const { chatId } = req.params;
  const { userId } = req.body;
  try {
    const chat = await db.get('SELECT * FROM chats WHERE id = ?', [chatId]);
    if (!chat || !chat.isGroup) {
      return res.status(404).json({ success: false, error: 'Группа не найдена' });
    }
    
    // Проверяем, что пользователь является администратором
    if (chat.groupAdminId !== req.userId) {
      return res.status(403).json({ success: false, error: 'Только администратор может удалять участников' });
    }
    
    let participants = JSON.parse(chat.participants);
    participants = participants.filter(id => id !== userId);
    
    await db.run(
      'UPDATE chats SET participants = ? WHERE id = ?',
      [JSON.stringify(participants), chatId]
    );
    
    // Уведомляем удаленного участника
    io.to(String(userId)).emit('group_left', { chatId });
    
    res.json({ success: true, participants });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// API: Удаление группы
app.delete('/api/chats/:chatId', authMiddleware, async (req, res) => {
  const { chatId } = req.params;
  try {
    const chat = await db.get('SELECT * FROM chats WHERE id = ?', [chatId]);
    if (!chat || !chat.isGroup) {
      return res.status(404).json({ success: false, error: 'Группа не найдена' });
    }
    
    // Проверяем, что пользователь является администратором
    if (chat.groupAdminId !== req.userId) {
      return res.status(403).json({ success: false, error: 'Только администратор может удалить группу' });
    }
    
    // Удаляем все сообщения группы
    await db.run('DELETE FROM messages WHERE chatId = ?', [chatId]);
    
    // Удаляем группу
    await db.run('DELETE FROM chats WHERE id = ?', [chatId]);
    
    // Уведомляем всех участников
    const participants = JSON.parse(chat.participants);
    participants.forEach(userId => {
      io.to(String(userId)).emit('group_deleted', { chatId });
    });
    
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// API: Удаление сообщения
app.delete('/api/chats/:chatId/messages/:messageId', authMiddleware, async (req, res) => {
  const { chatId, messageId } = req.params;
  try {
    const message = await db.get('SELECT * FROM messages WHERE id = ? AND chatId = ?', [messageId, chatId]);
    if (!message) {
      return res.status(404).json({ success: false, error: 'Сообщение не найдено' });
    }
    
    // Проверяем, что пользователь является отправителем сообщения
    if (message.senderId !== req.userId) {
      return res.status(403).json({ success: false, error: 'Можно удалять только свои сообщения' });
    }
    
    await db.run('DELETE FROM messages WHERE id = ?', [messageId]);
    
    // Уведомляем всех участников чата
    io.to(chatId).emit('message_deleted', { messageId, chatId });
    
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// API: Обновление профиля
app.post('/api/users/update', async (req, res) => {
  const { id, displayName, status, photoUrl } = req.body;
  await db.run(
    'UPDATE users SET displayName = ?, status = ?, photoUrl = ? WHERE id = ?',
    [displayName, status, photoUrl, id]
  );
  const user = await db.get('SELECT * FROM users WHERE id = ?', [id]);
  res.json({ success: true, user });
});

// Хранилище временных кодов OTP (в памяти для быстроты)
const otpStore = new Map();

// Функция для нормализации номера телефона для SMS.ru
function normalizePhoneNumber(phone) {
  // Убираем все нецифровые символы
  let normalized = phone.replace(/\D/g, '');
  
  // Если номер начинается с 8, заменяем на 7
  if (normalized.startsWith('8')) {
    normalized = '7' + normalized.substring(1);
  }
  
  // Если номер начинается с +7, убираем +
  if (phone.startsWith('+7')) {
    normalized = '7' + normalized.substring(1);
  }
  
  // Если номер не начинается с 7, добавляем 7 (для российских номеров)
  if (!normalized.startsWith('7') && normalized.length === 10) {
    normalized = '7' + normalized;
  }
  
  return normalized;
}

// API: Отправка OTP через SMS.ru
app.post('/api/auth/send-otp', async (req, res) => {
  let responseSent = false;
  
  const sendResponse = (statusCode, data) => {
    if (!responseSent) {
      responseSent = true;
      res.status(statusCode).json(data);
    }
  };
  
  try {
    const { phoneNumber } = req.body;

    if (!phoneNumber || phoneNumber.trim() === '') {
      return sendResponse(400, { success: false, message: 'Номер телефона не указан' });
    }

    // Вход для гостя
    if (phoneNumber === '1111111111') {
      return sendResponse(200, { success: true, message: 'Guest login enabled. Use code 0000' });
    }

    // Нормализуем номер телефона для SMS.ru
    const normalizedPhone = normalizePhoneNumber(phoneNumber);
    console.log(`[DEBUG] Original phone: ${phoneNumber}, Normalized: ${normalizedPhone}`);

    // Проверяем формат номера (должен быть 11 цифр для России)
    if (normalizedPhone.length !== 11 || !normalizedPhone.startsWith('7')) {
      console.error(`[ERROR] Invalid phone format: ${normalizedPhone}`);
      return sendResponse(400, { 
        success: false, 
        message: 'Неверный формат номера телефона. Используйте формат: +7XXXXXXXXXX' 
      });
    }

    const code = Math.floor(1000 + Math.random() * 9000).toString();
    
    // Сохраняем код для обоих форматов номера (оригинального и нормализованного)
    otpStore.set(phoneNumber, code);
    otpStore.set(normalizedPhone, code);
    console.log(`[DEBUG] Generated OTP for ${phoneNumber} (${normalizedPhone}): ${code}`);
    
    // Отправляем SMS через SMS.ru используя прямой HTTP запрос
    console.log(`[DEBUG] Attempting to send SMS to ${normalizedPhone} via SMS.ru API`);
    
    const smsText = `Ваш код подтверждения: ${code}`;
    const postData = querystring.stringify({
      api_id: SMS_RU_API_ID,
      to: normalizedPhone,
      msg: smsText,
      json: 1
    });
    
    const options = {
      hostname: 'sms.ru',
      port: 443,
      path: '/sms/send',
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(postData)
      }
    };
    
    // Создаем запрос
    const req = https.request(options, (smsRes) => {
      let responseData = '';
      
      smsRes.on('data', (chunk) => {
        responseData += chunk;
      });
      
      smsRes.on('end', () => {
        try {
          if (!responseData) {
            throw new Error('Empty response from SMS.ru');
          }
          
          const result = JSON.parse(responseData);
          console.log(`[DEBUG] SMS.ru API response:`, JSON.stringify(result, null, 2));
          
          if (result.status === 'OK' && result.status_code === 100) {
            console.log(`[DEBUG] SMS sent successfully to ${normalizedPhone}`);
            sendResponse(200, { success: true, message: 'SMS код отправлен' });
          } else {
            const errorCode = String(result.status_code || 'unknown');
            const errorText = result.status_text || 'Ошибка отправки SMS';
            console.error(`[ERROR] SMS send error for ${normalizedPhone}: Code ${errorCode}, Text: ${errorText}`);
            
            // Более детальные сообщения об ошибках на основе кодов SMS.ru
            let userMessage = 'Не удалось отправить SMS. Проверьте номер телефона и попробуйте еще раз.';
            if (errorCode === '202' || errorCode === '221') {
              userMessage = 'Номер телефона указан неверно. Используйте формат: +7XXXXXXXXXX';
            } else if (errorCode === '207') {
              userMessage = 'Недостаточно средств на счете SMS.ru. Обратитесь к администратору.';
            } else if (errorCode === '100') {
              userMessage = 'SMS код отправлен';
            }
            
            sendResponse(500, { 
              success: false, 
              message: userMessage,
              errorCode: errorCode,
              errorDetails: errorText
            });
          }
        } catch (parseError) {
          console.error(`[ERROR] Failed to parse SMS.ru response:`, parseError);
          console.error(`[ERROR] Response data:`, responseData);
          sendResponse(500, { 
            success: false, 
            message: 'Ошибка обработки ответа от SMS.ru. Попробуйте позже.',
            errorDetails: parseError.message
          });
        }
      });
    });
    
    // Устанавливаем таймаут на сокет (не на опции)
    req.setTimeout(10000, () => {
      console.error(`[ERROR] SMS.ru API request timeout`);
      req.destroy();
      sendResponse(500, { 
        success: false, 
        message: 'Таймаут при отправке SMS. Попробуйте позже.'
      });
    });
    
    req.on('error', (error) => {
      console.error(`[ERROR] SMS.ru API request error:`, error);
      sendResponse(500, { 
        success: false, 
        message: 'Ошибка подключения к SMS.ru. Попробуйте позже.',
        errorDetails: error.message
      });
    });
    
    // Отправляем данные и завершаем запрос
    req.write(postData);
    req.end();
  } catch (error) {
    console.error(`[ERROR] Unexpected error in send-otp:`, error);
    sendResponse(500, { 
      success: false, 
      message: 'Внутренняя ошибка сервера. Попробуйте позже.',
      errorDetails: error.message
    });
  }
});

app.post('/api/auth/verify-otp', async (req, res) => {
  const { phoneNumber, code, displayName } = req.body;
  
  if (!phoneNumber || !code) {
    return res.status(400).json({ success: false, message: 'Номер телефона и код обязательны' });
  }
  
  const isGuest = phoneNumber === '1111111111' && code === '0000';
  const normalizedPhone = normalizePhoneNumber(phoneNumber);
  
  // Проверяем код для обоих форматов номера
  const storedCode = otpStore.get(phoneNumber) || otpStore.get(normalizedPhone);
  const isValidCode = isGuest || storedCode === code || code === '1234'; // 1234 для теста

  if (isValidCode) {
    // Сохраняем оригинальный формат номера в БД
    let user = await db.get('SELECT * FROM users WHERE phoneNumber = ?', [phoneNumber]);
    if (!user) {
      // Также проверяем нормализованный формат
      user = await db.get('SELECT * FROM users WHERE phoneNumber = ?', [normalizedPhone]);
    }
    
    if (!user) {
      const id = Date.now().toString();
      const name = isGuest ? 'Гость' : (displayName || phoneNumber);
      await db.run('INSERT INTO users (id, phoneNumber, displayName) VALUES (?, ?, ?)', 
        [id, phoneNumber, name]);
      user = { id, phoneNumber, displayName: name };
      console.log(`[DEBUG] New user created: ${phoneNumber}`);
    }
    const token = jwt.sign({ id: user.id }, JWT_SECRET);
    // Удаляем использованный код из хранилища для обоих форматов
    otpStore.delete(phoneNumber);
    otpStore.delete(normalizedPhone);
    console.log(`[DEBUG] OTP verified successfully for ${phoneNumber}`);
    res.json({ success: true, token, user });
  } else {
    console.log(`[DEBUG] Invalid OTP code for ${phoneNumber}. Expected: ${storedCode}, Got: ${code}`);
    res.status(400).json({ success: false, message: 'Неверный код подтверждения. Проверьте SMS и попробуйте еще раз.' });
  }
});

// Поиск пользователей
app.get('/api/users/search', async (req, res) => {
  const { query } = req.query;
  const searchQuery = query || '';
  const users = await db.all(
    'SELECT id, phoneNumber, email, displayName, photoUrl FROM users WHERE phoneNumber LIKE ? OR displayName LIKE ? OR email LIKE ? LIMIT 50',
    [`%${searchQuery}%`, `%${searchQuery}%`, `%${searchQuery}%`]
  );
  res.json(users);
});

// Получение пользователя по ID
app.get('/api/users/:userId', authMiddleware, async (req, res) => {
  try {
    const user = await db.get('SELECT id, phoneNumber, email, displayName, photoUrl, status FROM users WHERE id = ?', [req.params.userId]);
    if (user) {
      res.json(user);
    } else {
      res.status(404).json({ success: false, error: 'User not found' });
    }
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// Создание чата
app.post('/api/chats/create', async (req, res) => {
  const { participants } = req.body;
  participants.sort();
  const chatId = participants.join('_');
  
  try {
    let chat = await db.get('SELECT * FROM chats WHERE id = ?', [chatId]);
    if (!chat) {
      const timestamp = Date.now();
      await db.run(
        'INSERT INTO chats (id, participants, lastMessageTimestamp, lastMessage) VALUES (?, ?, ?, ?)',
        [chatId, JSON.stringify(participants), timestamp, 'Чат создан']
      );
      chat = { id: chatId, participants, lastMessage: 'Чат создан', lastMessageTimestamp: timestamp };
      
      console.log(`[DEBUG] New chat created: ${chatId}`);
      
      participants.forEach(userId => {
        io.to(String(userId)).emit('chat_created', chat);
      });
    } else {
      // Даже если чат существует, возвращаем его с распарсенными участниками
      chat.participants = JSON.parse(chat.participants);
    }
    res.json(chat);
  } catch (e) {
    console.error(`[ERROR] Create chat error: ${e.message}`);
    res.status(500).json({ success: false, error: e.message });
  }
});

app.post('/api/upload', upload.single('file'), (req, res) => {
  res.json({ url: `/uploads/${req.file.filename}` });
});

// Получение списка чатов пользователя
app.get('/api/chats', authMiddleware, async (req, res) => {
  try {
    const userId = String(req.userId);
    console.log(`[DEBUG] Fetching chats for user ID: ${userId}`);
    
    const chats = await db.all('SELECT * FROM chats ORDER BY lastMessageTimestamp DESC');
    
    const userChats = chats.filter(chat => {
      try {
        const participants = typeof chat.participants === 'string' 
          ? JSON.parse(chat.participants) 
          : chat.participants;
        return Array.isArray(participants) && participants.map(String).includes(userId);
      } catch (e) {
        return false;
      }
    }).map(chat => {
      return { ...chat, participants: JSON.parse(chat.participants) };
    });

    console.log(`[DEBUG] Found ${userChats.length} matches for user ${userId}`);
    res.json(userChats);
  } catch (e) {
    console.error(`[ERROR] Fetch chats error: ${e.message}`);
    res.status(500).json({ success: false, error: e.message });
  }
});

app.get('/api/chats/:chatId/messages', authMiddleware, async (req, res) => {
  try {
    const messages = await db.all(
      'SELECT * FROM messages WHERE chatId = ? ORDER BY timestamp DESC LIMIT 100',
      [req.params.chatId]
    );
    res.json(messages);
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

const userSockets = new Map();

io.use((socket, next) => {
  const token = socket.handshake.auth.token;
  console.log(`[DEBUG] Socket Auth attempt with token: ${token}`);
  if (token) {
    jwt.verify(token, JWT_SECRET, (err, decoded) => {
      if (err) {
        console.error(`[ERROR] Socket JWT verify error: ${err.message}`);
        return next(new Error('Auth error'));
      }
      socket.userId = decoded.id;
      console.log(`[DEBUG] Socket Auth success for user: ${socket.userId}`);
      next();
    });
  } else {
    console.error(`[ERROR] Socket Auth error: No token provided`);
    next(new Error('Auth error'));
  }
});

io.on('connection', (socket) => {
  console.log(`[DEBUG] User connected: ${socket.userId}`);
  userSockets.set(socket.userId, socket.id);
  socket.join(String(socket.userId));

  socket.on('join_chat', (chatId) => {
    socket.join(chatId);
  });

  socket.on('send_message', async (data) => {
    const { chatId, text, type, mediaUrl, replyToMessageId } = data;
    const timestamp = Date.now();
    const message = {
      id: timestamp.toString(),
      chatId,
      senderId: socket.userId,
      text,
      type,
      mediaUrl,
      timestamp,
      replyToMessageId: replyToMessageId || null
    };

    try {
      await db.run(
        'INSERT INTO messages (id, chatId, senderId, text, type, mediaUrl, timestamp, replyToMessageId) VALUES (?,?,?,?,?,?,?,?)',
        [message.id, message.chatId, message.senderId, message.text, message.type, message.mediaUrl, message.timestamp, message.replyToMessageId]
      );

      await db.run(
        'UPDATE chats SET lastMessage = ?, lastMessageTimestamp = ? WHERE id = ?',
        [text || type, timestamp, chatId]
      );

      console.log(`[DEBUG] Message saved and chat updated: ${chatId}`);
      io.to(chatId).emit('new_message', message);
    } catch (e) {
      console.error(`[ERROR] Send message error: ${e.message}`);
    }
  });

  socket.on('call_user', (data) => {
    const { to, channelName, type } = data;
    const targetSocketId = userSockets.get(to);
    if (targetSocketId) {
      io.to(targetSocketId).emit('incoming_call', {
        from: socket.userId,
        channelName,
        type
      });
    }
  });

  socket.on('group_call', (data) => {
    const { participants, channelName, type } = data;
    // Отправляем уведомление всем участникам группы
    participants.forEach(participantId => {
      const targetSocketId = userSockets.get(participantId);
      if (targetSocketId && participantId !== socket.userId) {
        io.to(targetSocketId).emit('incoming_group_call', {
          from: socket.userId,
          channelName,
          type,
          participants
        });
      }
    });
  });

  socket.on('disconnect', () => {
    userSockets.delete(socket.userId);
  });
});

// Webhook endpoint для SMS.ru (должен отвечать "100")
app.post('/api/sms/webhook', (req, res) => {
  console.log('[DEBUG] SMS.ru webhook received:', JSON.stringify(req.body, null, 2));
  // SMS.ru требует ответ "100" в теле ответа
  res.status(200).send('100');
});

// Обработчик для несуществующих маршрутов (404)
app.use((req, res) => {
  res.status(404).json({ 
    success: false, 
    error: 'Маршрут не найден',
    path: req.path 
  });
});

// Общий обработчик ошибок
app.use((err, req, res, next) => {
  console.error(`[ERROR] Unhandled error:`, err);
  res.status(err.status || 500).json({
    success: false,
    error: err.message || 'Внутренняя ошибка сервера',
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack })
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});
