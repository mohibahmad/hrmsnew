import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'home_screen.dart';

void main() {
  runApp(const WorkerManagementApp());
}

class WorkerManagementApp extends StatelessWidget {
  const WorkerManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Worker Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'SF Pro Display',
        scaffoldBackgroundColor: const Color(0xFFF9FAFC),
      ),
      home: const AddNewWorkerScreen(),
    );
  }
}

class AddNewWorkerScreen extends StatelessWidget {
  const AddNewWorkerScreen({super.key});

  final Color textDark = const Color(0xFF111111);
  final Color formBgGrey = const Color(0xFFF3F5F8);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Row(
        children: [
          // ================= LEFT SIDEBAR =================
          SidebarWidget(
            selectedIndex: 1,
            onItemSelected: (index) {
              Navigator.of(context).pop();
            },
          ),

          // ================= MAIN CONTENT AREA =================
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Top Header Area ---
                Container(
                  height: 94,
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Padding(
                              padding: EdgeInsets.only(top: 2.0),
                              child: Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 24),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Add New Worker',
                                style: TextStyle(
                                  color: textDark,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Fill in the worker details to get started.',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Save Button
                      Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8EDF8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Save',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // --- Main Form Content ---
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        
                        // --- Tabs Section ---
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ]
                          ),
                          child: Row(
                            children: [
                              Expanded(child: _buildTopTab('Worker Detail', isActive: true)),
                              Expanded(child: _buildTopTab('Experience')),
                              Expanded(child: _buildTopTab('Documentation')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // --- Sub-header ("Personal Information") ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Personal Information',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                            Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                              ),
                              child: Row(
                                children: const [
                                  Text(
                                    'Next Step',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward, size: 18, color: Colors.black),
                                ],
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 24),

                        // --- Form Grid & Right Panel ---
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // === LEFT: Input Form Area ===
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: formBgGrey,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(child: _buildInputField('Worker Name:', 'Enter your name')),
                                        const SizedBox(width: 24),
                                        Expanded(child: _buildInputField('Worker Father/Husband Name:', 'Enter your name')),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    Row(
                                      children: [
                                        Expanded(child: _buildInputField('Worker E-mail:', 'Enter your email')),
                                        const SizedBox(width: 24),
                                        Expanded(child: _buildInputField('Contact no:', '0000000000')),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    Row(
                                      children: [
                                        Expanded(child: _buildInputField('National ID:', 'Enter your national id')),
                                        const SizedBox(width: 24),
                                        Expanded(child: _buildInputField('Professed Religion:', 'Enter your religion')),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    Row(
                                      children: [
                                        Expanded(child: _buildInputField('Worker Date of Birth:', '00/00/0000', suffixIcon: Icons.calendar_month)),
                                        const SizedBox(width: 24),
                                        Expanded(child: _buildInputField('Gender:', 'Male', suffixIcon: Icons.arrow_drop_down)),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    _buildInputField('Worker Address:', 'Enter your address', isTextArea: true),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 32),

                            // === RIGHT: Profile Upload & Status ===
                            Expanded(
                              flex: 1,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Profile Upload Section
                                  const Text(
                                    'Worker Profile',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Container(
                                    height: 240,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.01),
                                          blurRadius: 10,
                                          offset: const Offset(0, 5),
                                        )
                                      ]
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Image.asset(
                                          'assets/profile_placeholder.png',
                                          height: 64,
                                          width: 64,
                                          fit: BoxFit.cover,
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'Upload Profile',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Upload a profile image\nPNG, JPG or PDF',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.black38,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  
                                  // Relationship Status Section
                                  const Text(
                                    'Relationship Status:',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      _buildCustomRadio(label: 'Married', isSelected: true),
                                      const SizedBox(width: 40),
                                      _buildCustomRadio(label: 'Single', isSelected: false),
                                    ],
                                  )
                                ],
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTab(String title, {bool isActive = false}) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFE8EEF9) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.black,
          fontSize: 15,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }

  Widget _buildInputField(String label, String hint, {IconData? suffixIcon, bool isTextArea = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: isTextArea ? 90 : 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: isTextArea ? Alignment.topLeft : Alignment.center,
          child: TextField(
            maxLines: isTextArea ? 4 : 1,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black,
              fontFamily: 'SF Pro Display',
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: isTextArea ? const EdgeInsets.only(top: 14) : null,
              suffixIcon: suffixIcon != null 
                ? Icon(suffixIcon, color: Colors.grey.shade400, size: 22) 
                : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomRadio({required String label, required bool isSelected}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: isSelected 
              ? Center(
                  child: Container(
                    width: 10, height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black,
                    ),
                  ),
                ) 
              : const SizedBox(),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    );
  }
}
