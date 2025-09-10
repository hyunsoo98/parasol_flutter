import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart'; - 제거됨
import 'package:fluttertoast/fluttertoast.dart';

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  // final FirebaseAuth _auth = FirebaseAuth.instance; - 제거됨
  
  String? _verificationId;
  bool _isLoading = false;
  bool _isOtpSent = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('전화번호 인증'),
        backgroundColor: const Color(0xFF2F3DA3),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            const Text(
              '전화번호로 로그인',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            
            if (!_isOtpSent) ...[
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '전화번호',
                  hintText: '+82 10-1234-5678',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _sendOTP,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2F3DA3),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('인증번호 발송'),
              ),
            ] else ...[
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '인증번호',
                  hintText: '6자리 인증번호 입력',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyOTP,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2F3DA3),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('인증 완료'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isOtpSent = false;
                    _otpController.clear();
                  });
                },
                child: const Text('다른 번호로 재시도'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _sendOTP() async {
    if (_phoneController.text.trim().isEmpty) {
      _showToast('전화번호를 입력해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // TODO: 실제 SMS 인증 서비스 구현 (Firebase 대신)
      await Future.delayed(const Duration(seconds: 2)); // 시뮬레이션
      
      setState(() {
        _isOtpSent = true;
        _isLoading = false;
        _verificationId = 'temp_verification_id'; // 임시 ID
      });
      
      _showToast('인증번호가 발송되었습니다.');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showToast('인증번호 발송에 실패했습니다. 다시 시도해주세요.');
    }
  }

  Future<void> _verifyOTP() async {
    if (_otpController.text.trim().isEmpty) {
      _showToast('인증번호를 입력해주세요.');
      return;
    }

    if (_otpController.text.trim().length != 6) {
      _showToast('6자리 인증번호를 정확히 입력해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // TODO: 실제 OTP 검증 로직 구현
      await Future.delayed(const Duration(seconds: 2)); // 시뮬레이션
      
      // 임시로 123456을 올바른 인증번호로 설정
      if (_otpController.text == '123456') {
        _showToast('인증이 완료되었습니다.');
        
        // 메인 화면으로 이동
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
        _showToast('잘못된 인증번호입니다. (테스트용: 123456)');
      }
    } catch (e) {
      _showToast('인증에 실패했습니다. 다시 시도해주세요.');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }
}