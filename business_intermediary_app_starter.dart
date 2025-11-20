// Business Intermediary - Flutter starter
// File: lib/main.dart
// Asset (poster): /mnt/data/Design sem nome.png

/*
  Instruções rápidas:
  1. Coloca a imagem enviada em: /assets/images/design_poster.png
     (no ambiente local, a path original é: /mnt/data/Design sem nome.png)
  2. Atualiza pubspec.yaml para incluir a pasta assets:

     flutter:
       assets:
         - assets/images/design_poster.png

  3. Executa: flutter run

  O projeto abaixo é um scaffold mínimo com as telas principais:
  - Splash
  - Home (lista de anúncios)
  - Publicar anúncio
  - Chat (simplificado)
  - Perfil do vendedor
  - Painel Admin (apenas layout)

  Próximos passos que posso fazer automaticamente se quiseres:
  - Gerar protótipos UI (PNG) das telas
  - Gerar apk debug/release e instruções de instalação
  - Criar backend básico em Firebase (Auth, Firestore, Storage)
  - Implementar integração de pagamentos via Multicaixa (se forneces API)
*/

import 'package:flutter/material.dart';

void main() => runApp(BusinessIntermediaryApp());

class BusinessIntermediaryApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Business Intermediary',
      theme: ThemeData(
        primaryColor: Color(0xFFf2b705),
        accentColor: Color(0xFF222222),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(seconds: 2), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomePage()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Use the poster image as branding on splash
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                image: DecorationImage(
                  image: AssetImage('assets/images/design_poster.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            SizedBox(height: 20),
            Text('Business Intermediary', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('A solução para as tuas vendas', style: TextStyle(color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    ListingsPage(),
    PublishPage(),
    ChatPage(),
    ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Business Intermediary'),
        backgroundColor: Color(0xFF222222),
        elevation: 0,
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: Color(0xFFf2b705),
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Anúncios'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box), label: 'Publicar'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
      drawer: AppDrawer(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Color(0xFFf2b705),
        child: Icon(Icons.search, color: Colors.white),
        onPressed: () {},
      ),
    );
  }
}

class ListingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Example list of product cards
    return ListView.builder(
      padding: EdgeInsets.all(12),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Card(
          margin: EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            leading: Container(
              width: 70,
              height: 70,
              color: Colors.grey[300],
              child: Icon(Icons.image, size: 36, color: Colors.grey[700]),
            ),
            title: Text('Produto Exemplo #${index + 1}', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Categoria • Preço: 100.000 Kz'),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(primary: Color(0xFFf2b705)),
              child: Text('Quero'),
              onPressed: () {
                // Simula pedido para o intermediário
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text('Pedido enviado'),
                    content: Text('O teu pedido foi enviado ao intermediário.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: Text('OK'))
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class PublishPage extends StatefulWidget {
  @override
  _PublishPageState createState() => _PublishPageState();
}

class _PublishPageState extends State<PublishPage> {
  final _formKey = GlobalKey<FormState>();
  String title = '';
  String price = '';
  String category = 'Telefones';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Publicar Anúncio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            TextFormField(
              decoration: InputDecoration(labelText: 'Título'),
              onSaved: (v) => title = v ?? '',
            ),
            TextFormField(
              decoration: InputDecoration(labelText: 'Preço'),
              keyboardType: TextInputType.number,
              onSaved: (v) => price = v ?? '',
            ),
            DropdownButtonFormField<String>(
              value: category,
              items: ['Telefones', 'Carros', 'Casas', 'Eletrodomésticos', 'Vestuário']
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => category = v!),
              decoration: InputDecoration(labelText: 'Categoria'),
            ),
            SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(primary: Color(0xFF222222)),
              onPressed: () {
                _formKey.currentState?.save();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Anúncio enviado para aprovação')));
              },
              child: Text('Enviar para aprovação'),
            )
          ],
        ),
      ),
    );
  }
}

class ChatPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('Chat interno - em desenvolvimento'),
    );
  }
}

class ProfilePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Perfil', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          ListTile(
            leading: CircleAvatar(child: Icon(Icons.person)),
            title: Text('Business Intermediary'),
            subtitle: Text('+244 941963554'),
          ),
          SizedBox(height: 12),
          Text('Minhas Publicações', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Expanded(child: Center(child: Text('Lista de anúncios do vendedor'))),
        ],
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Color(0xFF222222)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Business Intermediary', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('A solução para as tuas vendas', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          ListTile(leading: Icon(Icons.dashboard), title: Text('Painel Admin'), onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => AdminPanel())); }),
          ListTile(leading: Icon(Icons.info), title: Text('Contactos'), onTap: () {}),
        ],
      ),
    );
  }
}

class AdminPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Painel Admin'), backgroundColor: Color(0xFF222222)),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Estatísticas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Card(child: Padding(padding: EdgeInsets.all(12), child: Column(children: [Text('Anúncios'), SizedBox(height: 8), Text('120')])))),
                SizedBox(width: 12),
                Expanded(child: Card(child: Padding(padding: EdgeInsets.all(12), child: Column(children: [Text('Pedidos'), SizedBox(height: 8), Text('45')])))),
              ],
            ),
            SizedBox(height: 12),
            Text('Aprovações pendentes', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(child: Center(child: Text('Lista de aprovações'))),
          ],
        ),
      ),
    );
  }
}
