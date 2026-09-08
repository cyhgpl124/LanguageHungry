import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('서비스 약관')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          Text('이용약관',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          Text(
            'LANGGRY는 사용자의 언어 학습을 돕는 서비스입니다. 사용자는 정확한 가입 정보를 제공해야 하며, 타인의 계정을 이용하거나 서비스를 방해해서는 안 됩니다. 서비스는 안정적인 운영을 위해 필요한 경우 사전 고지 후 일부 기능을 변경할 수 있습니다.',
          ),
          SizedBox(height: 28),
          Text('개인정보 처리방침',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          Text(
            '서비스 제공을 위해 이메일, 이름, 휴대폰 번호와 학습 기록을 수집할 수 있습니다. 수집한 정보는 회원 식별, 계정 복구, 서비스 개선 목적에만 사용하며 법령에 따른 경우를 제외하고 제3자에게 제공하지 않습니다. 사용자는 언제든지 개인정보 열람·정정·삭제를 요청할 수 있습니다.',
          ),
          SizedBox(height: 28),
          Text('스토어 및 외부 로그인 안내',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          Text(
            'Google 등 외부 계정으로 로그인하는 경우 해당 제공자의 약관과 개인정보 처리방침이 함께 적용됩니다. iOS에서 제3자 로그인을 제공하는 경우 App Store 정책에 따라 Apple 로그인 제공 여부를 검토하고 동일한 수준의 개인정보 보호 선택권을 제공합니다. 결제나 구독 기능이 추가될 때에는 Apple 및 Google Play 결제 정책을 준수합니다.',
          ),
        ],
      ),
    );
  }
}
