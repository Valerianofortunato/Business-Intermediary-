git clone https://github.com/seu-usuario/business-intermediary.git
cd business-intermediary
import express from 'express';
import cors from 'cors';
import { createServer } from 'http';
import { initDB } from './database';
import authRoutes from './routes/auth';
import productRoutes from './routes/products';
import walletRoutes from './routes/wallet';
import adminRoutes from './routes/admin';

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Rotas
app.use('/api/auth', authRoutes);
app.use('/api/products', productRoutes);
app.use('/api/wallet', walletRoutes);
app.use('/api/admin', adminRoutes);

// Health check
app.get('/api/health', (req, res) => res.json({ status: 'ok' }));

const server = createServer(app);
const PORT = process.env.PORT || 5000;

initDB().then(() => {
  server.listen(PORT, () => console.log(`🚀 Backend rodando na porta ${PORT}`));
});import { Pool } from 'pg';

export const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  database: 'business_intermediary',
  user: 'postgres',
  password: 'postgres',
  port: 5432,
});

export const initDB = async () => {
  await pool.query(`
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

    -- Usuários
    CREATE TABLE IF NOT EXISTS users (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      phone VARCHAR(9) UNIQUE NOT NULL,
      email VARCHAR(255) UNIQUE NOT NULL,
      password_hash VARCHAR(255) NOT NULL,
      first_name VARCHAR(100),
      last_name VARCHAR(100),
      birth_date DATE,
      account_type VARCHAR(20) CHECK (account_type IN ('individual', 'company')),
      company_name VARCHAR(255),
      status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'blocked')),
      id_front_image VARCHAR(255),
      id_back_image VARCHAR(255),
      selfie_image VARCHAR(255),
      balance INTEGER DEFAULT 0, -- em Kz
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    );

    -- Produtos
    CREATE TABLE IF NOT EXISTS products (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      user_id UUID REFERENCES users(id),
      title VARCHAR(255) NOT NULL,
      description TEXT NOT NULL,
      category VARCHAR(100) NOT NULL,
      condition VARCHAR(20) CHECK (condition IN ('new', 'used')),
      price INTEGER NOT NULL, -- em Kz
      images TEXT[] NOT NULL, -- array de URLs
      status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'sold', 'paused')),
      promoted BOOLEAN DEFAULT false,
      promoted_until TIMESTAMP,
      created_at TIMESTAMP DEFAULT NOW()
    );

    -- Transações (Escrow)
    CREATE TABLE IF NOT EXISTS transactions (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      buyer_id UUID REFERENCES users(id),
      seller_id UUID REFERENCES users(id),
      product_id UUID REFERENCES products(id),
      amount INTEGER NOT NULL,
      commission INTEGER NOT NULL,
      status VARCHAR(20) DEFAULT 'held' CHECK (status IN ('held', 'released', 'refunded', 'cancelled')),
      created_at TIMESTAMP DEFAULT NOW(),
      released_at TIMESTAMP,
      auto_release_at TIMESTAMP DEFAULT NOW() + INTERVAL '48 hours'
    );

    -- Notificações
    CREATE TABLE IF NOT EXISTS notifications (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      user_id UUID REFERENCES users(id),
      type VARCHAR(50) NOT NULL,
      message TEXT NOT NULL,
      read BOOLEAN DEFAULT false,
      created_at TIMESTAMP DEFAULT NOW()
    );

    -- Admin Activity Log
    CREATE TABLE IF NOT EXISTS admin_logs (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      admin_id UUID REFERENCES users(id),
      action VARCHAR(100) NOT NULL,
      target_user_id UUID,
      details JSONB,
      created_at TIMESTAMP DEFAULT NOW()
    );

    -- Usuário admin inicial
    INSERT INTO users (phone, email, password_hash, account_type, status, first_name, last_name)
    VALUES ('admin123', 'admin@businessintermediary.ao', '$2b$10$YourHashedPassword', 'individual', 'approved', 'Admin', 'Master')
    ON CONFLICT DO NOTHING;
  `);
};import { Router } from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import multer from 'multer';
import { pool } from '../database';
import { sendSMS, sendEmail } from '../utils/notifications';

const router = Router();
const upload = multer({ dest: 'uploads/' });

// Registo Individual
router.post('/register/individual', async (req, res) => {
  const { firstName, lastName, birthDate, email, phone, password } = req.body;
  
  const hashed = await bcrypt.hash(password, 10);
  
  try {
    const result = await pool.query(
      `INSERT INTO users (first_name, last_name, birth_date, email, phone, password_hash, account_type) 
       VALUES ($1, $2, $3, $4, $5, $6, 'individual') RETURNING id`,
      [firstName, lastName, birthDate, email, phone, hashed]
    );
    
    // Enviar código por SMS/email
    const code = Math.random().toString().substr(2, 6);
    await sendSMS(phone, `Código de confirmação: ${code}`);
    
    res.json({ success: true, userId: result.rows[0].id });
  } catch (err) {
    res.status(400).json({ error: 'Número ou email já existe' });
  }
});

// Upload de documentos
router.post('/upload-docs', upload.fields([
  { name: 'idFront', maxCount: 1 },
  { name: 'idBack', maxCount: 1 },
  { name: 'selfie', maxCount: 1 }
]), async (req, res) => {
  const { userId } = req.body;
  const files = req.files as { [fieldname: string]: Express.Multer.File[] };
  
  await pool.query(
    `UPDATE users SET 
     id_front_image = $1, id_back_image = $2, selfie_image = $3,
     status = 'pending' WHERE id = $4`,
    [files.idFront[0].path, files.idBack[0].path, files.selfie[0].path, userId]
  );
  
  res.json({ success: true });
});

// Login
router.post('/login', async (req, res) => {
  const { phone, password } = req.body;
  const result = await pool.query('SELECT * FROM users WHERE phone = $1', [phone]);
  
  if (!result.rows[0]) return res.status(401).json({ error: 'Credenciais inválidas' });
  
  const valid = await bcrypt.compare(password, result.rows[0].password_hash);
  if (!valid) return res.status(401).json({ error: 'Credenciais inválidas' });
  
  const token = jwt.sign({ userId: result.rows[0].id }, 'your-secret-key', { expiresIn: '7d' });
  res.json({ token, user: result.rows[0] });
});import { Router } from 'express';
import { pool } from '../database';
import { authMiddleware } from '../middleware/auth';

const router = Router();

// Listar produtos
router.get('/', async (req, res) => {
  const result = await pool.query(`
    SELECT p.*, u.phone as seller_phone 
    FROM products p 
    JOIN users u ON p.user_id = u.id 
    WHERE p.status = 'active' 
    ORDER BY p.promoted DESC, p.created_at DESC
  `);
  res.json(result.rows);
});

// Publicar produto
router.post('/', authMiddleware, async (req, res) => {
  const { title, description, category, condition, price, images } = req.body;
  
  const result = await pool.query(
    `INSERT INTO products (user_id, title, description, category, condition, price, images) 
     VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
    [req.userId, title, description, category, condition, price, images]
  );
  
  res.json(result.rows[0]);
});

// Comprar produto
router.post('/:id/buy', authMiddleware, async (req, res) => {
  const productId = req.params.id;
  
  const product = await pool.query('SELECT * FROM products WHERE id = $1', [productId]);
  if (!product.rows[0]) return res.status(404).json({ error: 'Produto não encontrado' });
  
  const buyer = await pool.query('SELECT balance FROM users WHERE id = $1', [req.userId]);
  const seller = await pool.query('SELECT balance FROM users WHERE id = $1', [product.rows[0].user_id]);
  
  const amount = product.rows[0].price;
  const commission = Math.floor(amount * 0.1); // 10% temporário
  
  if (buyer.rows[0].balance < amount) {
    return res.status(400).json({ error: 'Saldo insuficiente' });
  }
  
  // Criar transação escrow
  const tx = await pool.query(
    `INSERT INTO transactions (buyer_id, seller_id, product_id, amount, commission, status) 
     VALUES ($1, $2, $3, $4, $5, 'held') RETURNING id`,
    [req.userId, product.rows[0].user_id, productId, amount, commission]
  );
  
  // Deduzir do comprador
  await pool.query('UPDATE users SET balance = balance - $1 WHERE id = $2', [amount, req.userId]);
  
  // Marcar produto como vendido
  await pool.query("UPDATE products SET status = 'sold' WHERE id = $1", [productId]);
  
  res.json({ success: true, transactionId: tx.rows[0].id });
});

// Confirmar receção
router.post('/confirm-receipt/:transactionId', authMiddleware, async (req, res) => {
  const tx = await pool.query(
    'SELECT * FROM transactions WHERE id = $1 AND buyer_id = $2',
    [req.params.transactionId, req.userId]
  );
  
  if (!tx.rows[0]) return res.status(404).json({ error: 'Transação não encontrada' });
  
  // Liberar para vendedor
  await pool.query(
    `UPDATE users SET balance = balance + $1 WHERE id = $2`,
    [tx.rows[0].amount - tx.rows[0].commission, tx.rows[0].seller_id]
  );
  
  // Atualizar transação
  await pool.query(
    "UPDATE transactions SET status = 'released', released_at = NOW() WHERE id = $1",
    [req.params.transactionId]
  );
  
  res.json({ success: true });
});import { Router } from 'express';
import { pool } from '../database';
import { authMiddleware } from '../middleware/auth';

const router = Router();

// Middleware de admin
const adminOnly = async (req, res, next) => {
  const user = await pool.query('SELECT * FROM users WHERE id = $1', [req.userId]);
  if (user.rows[0].phone !== 'admin123') {
    return res.status(403).json({ error: 'Acesso restrito' });
  }
  next();
};

// Aprovar KYC
router.post('/approve-kyc/:userId', authMiddleware, adminOnly, async (req, res) => {
  await pool.query("UPDATE users SET status = 'approved' WHERE id = $1", [req.params.userId]);
  res.json({ success: true });
});

// Rejeitar KYC
router.post('/reject-kyc/:userId', authMiddleware, adminOnly, async (req, res) => {
  await pool.query("UPDATE users SET status = 'rejected' WHERE id = $1", [req.params.userId]);
  res.json({ success: true });
});

// Listar transações
router.get('/transactions', authMiddleware, adminOnly, async (req, res) => {
  const result = await pool.query(`
    SELECT t.*, u1.phone as buyer_phone, u2.phone as seller_phone 
    FROM transactions t
    JOIN users u1 ON t.buyer_id = u1.id
    JOIN users u2 ON t.seller_id = u2.id
    ORDER BY t.created_at DESC
  `);
  res.json(result.rows);
});

// Alterar comissão dinâmica (guardar em cache Redis)
router.post('/commission-rate', authMiddleware, adminOnly, async (req, res) => {
  const { rate } = req.body; // e.g., 0.1 para 10%
  // Aqui você armazenaria no Redis ou config table
  res.json({ success: true, newRate: rate });
});import React, { useState } from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { ThemeProvider, createTheme } from '@mui/material';
import Register from './pages/Register';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import ProductDetail from './pages/ProductDetail';
import Wallet from './pages/Wallet';
import './App.css';

const theme = createTheme({
  palette: {
    primary: { main: '#1976d2' },
    secondary: { main: '#dc004e' },
  },
});

function App() {
  const [token, setToken] = useState(localStorage.getItem('token') || '');

  return (
    <ThemeProvider theme={theme}>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Login setToken={setToken} />} />
          <Route path="/register" element={<Register />} />
          <Route path="/dashboard" element={<Dashboard token={token} />} />
          <Route path="/product/:id" element={<ProductDetail token={token} />} />
          <Route path="/wallet" element={<Wallet token={token} />} />
        </Routes>
      </BrowserRouter>
    </Theme Provider>
  );
}

export default App;import React, { useEffect, useState } from 'react';
import { Grid, Card, CardMedia, CardContent, Typography, Button } from '@mui/material';
import { useNavigate } from 'react-router-dom';
import api from '../utils/api';

interface Product {
  id: string;
  title: string;
  price: number;
  images: string[];
  seller_phone: string;
}

export default function Dashboard({ token }: { token: string }) {
  const [products, setProducts] = useState<Product[]>([]);
  const navigate = useNavigate();

  useEffect(() => {
    api.get('/products').then(res => setProducts(res.data));
  }, []);

  const buyProduct = async (productId: string) => {
    await api.post(`/products/${productId}/buy`, {}, { headers: { Authorization: token } });
    alert('Compra efetuada! Verifique sua wallet.');
  };

  return (
    <Grid container spacing={3} style={{ padding: 20 }}>
      {products.map(p => (
        <Grid item xs={12} sm={6} md={4} key={p.id}>
          <Card>
            <CardMedia component="img" height="200" image={p.images[0]} />
            <CardContent>
              <Typography variant="h6">{p.title}</Typography>
              <Typography>{p.price.toLocaleString()} Kz</Typography>
              <Typography variant="body2">Vendedor: {p.seller_phone}</Typography>
              <Button onClick={() => buyProduct(p.id)} variant="contained" fullWidth>
                Comprar
              </Button>
            </CardContent>
          </Card>
        </Grid>
      ))}
    </Grid>
  );
}import React, { useState } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { ThemeProvider, createTheme } from '@mui/material';
import Login from './pages/Login';
import Users from './pages/Users';
import Transactions from './pages/Transactions';
import './App.css';

const theme = createTheme({
  palette: { primary: { main: '#d32f2f' } },
});

function App() {
  const [token, setToken] = useState(localStorage.getItem('adminToken') || '');

  return (
    <ThemeProvider theme={theme}>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Login setToken={setToken} />} />
          <Route path="/users" element={token ? <Users token={token} /> : <Navigate to="/" />} />
          <Route path="/transactions" element={token ? <Transactions token={token} /> : <Navigate to="/" />} />
        </Routes>
      </BrowserRouter>
    </ThemeProvider>
  );
}

export default App;import React, { useEffect, useState } from 'react';
import { Table, TableBody, TableCell, TableHead, TableRow, Button } from '@mui/material';
import api from '../utils/api';

interface User {
  id: string;
  phone: string;
  status: string;
  id_front_image: string;
}

export default function Users({ token }: { token: string }) {
  const [users, setUsers] = useState<User[]>([]);

  useEffect(() => {
    api.get('/admin/users', { headers: { Authorization: token } }).then(res => setUsers(res.data));
  }, [token]);

  const approve = (userId: string) => {
    api.post(`/admin/approve-kyc/${userId}`, {}, { headers: { Authorization: token } }).then(() => {
      setUsers(users.map(u => u.id === userId ? { ...u, status: 'approved' } : u));
    });
  };

  return (
    <Table>
      <TableHead>
        <TableRow>
          <TableCell>Telefone</TableCell>
          <TableCell>Status</TableCell>
          <TableCell>Ações</TableCell>
        </TableRow>
      </TableHead>
      <TableBody>
        {users.map(u => (
          <TableRow key={u.id}>
            <TableCell>{u.phone}</TableCell>
            <TableCell>{u.status}</TableCell>
            <TableCell>
              {u.status === 'pending' && (
                <Button onClick={() => approve(u.id)} color="primary">
                  Aprovar
                </Button>
              )}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}version: '3.8'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: business_intermediary
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

  backend:
    build: ./backend
    ports:
      - "5000:5000"
    environment:
      DB_HOST: postgres
      JWT_SECRET: super-secret-jwt-key
    depends_on:
      - postgres
    volumes:
      - ./uploads:/app/uploads

  frontend:
    build: ./frontend
    ports:
      - "3000:3000"

  admin:
    build: ./admin
    ports:
      - "3001:3001"

volumes:
  pgdata:FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build
EXPOSE 5000
CMD ["node", "dist/index.js"]FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/build /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]# 1. Clonar
git clone https://github.com/seu-usuario/business-intermediary.git
cd business-intermediary

# 2. Subir tudo
docker-compose up --build

# 3. Aceder
# Frontend: http://localhost:3000
# Admin: http://localhost:3001 (login: admin123 / 123456)

# 4. População inicial (opcional)
docker-compose exec backend npm run seed
git add .
git commit -m "Initial MVP"
git push originforneçoço
