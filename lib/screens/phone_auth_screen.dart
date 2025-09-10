import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttertoast/fluttertoast.dart';

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  String? _verificationId;
  bool _isLoading = false;
  bool _isOtpSent = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyPhoneNumber() async {
    final phoneNumber = '+82${_phoneController.text.trim()}';
    
    if (_phoneController.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: '전화번호를 입력해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // 자동 인증 완료 (일부 기기에서만 작동)
        await _signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        setState(() {
          _isLoading = false;
        });
        Fluttertoast.showToast(msg: '인증 실패: ${e.message}');
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() {
          _verificationId = verificationId;
          _isLoading = false;
          _isOtpSent = true;
        });
        Fluttertoast.showToast(msg: 'OTP가 전송되었습니다.');
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
      timeout: const Duration(seconds: 60),
    );
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.trim().isEmpty || _verificationId == null) {
      Fluttertoast.showToast(msg: 'OTP를 입력해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text.trim(),
      );
      
      await _signInWithCredential(credential);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      Fluttertoast.showToast(msg: 'OTP 인증 실패: $e');
    }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      final userCredential = await _auth.signInWithCredential(credential);
      
      setState(() {
        _isLoading = false;
      });
      
      if (userCredential.user != null) {
        Fluttertoast.showToast(msg: '로그인 성공!');
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        Fluttertoast.showToast(msg: '로그인에 실패했습니다. 다시 시도해주세요.');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      // Firebase 에러 타입별로 더 정확한 메시지 표시
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'invalid-verification-code':
            Fluttertoast.showToast(msg: '잘못된 인증번호입니다. 다시 확인해주세요.');
            break;
          case 'invalid-verification-id':
            Fluttertoast.showToast(msg: '인증 세션이 만료되었습니다. 다시 시도해주세요.');
            break;
          case 'session-expired':
            Fluttertoast.showToast(msg: '인증 세션이 만료되었습니다. 다시 시도해주세요.');
            break;
          default:
            // 사용자가 이미 로그인되어 있는지 확인
            if (_auth.currentUser != null) {
              Fluttertoast.showToast(msg: '로그인 성공!');
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/home');
              }
              return;
            }
            Fluttertoast.showToast(msg: '로그인 실패: ${e.message}');
        }
      } else {
        // 예상치 못한 에러가 발생했지만 사용자가 로그인되어 있는지 확인
        if (_auth.currentUser != null) {
          Fluttertoast.showToast(msg: '로그인 성공!');
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/home');
          }
        } else {
          Fluttertoast.showToast(msg: '로그인 실패: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('전화번호 인증'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_isOtpSent) ...[
              const Text(
                '전화번호를 입력해주세요',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('+82', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: '01012345678',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyPhoneNumber,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('인증번호 전송'),
              ),
            ] else ...[
              const Text(
                'OTP를 입력해주세요',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  hintText: '6자리 인증번호',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyOtp,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('인증 완료'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isOtpSent = false;
                    _verificationId = null;
                    _otpController.clear();
                  });
                },
                child: const Text('전화번호 다시 입력'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}