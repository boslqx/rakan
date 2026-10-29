/// Text of the Terms & Conditions and Privacy Policy shown at sign-up
/// (register screen checkbox) and from Settings.
///
/// Kept as plain Dart constants so the documents work offline and ship
/// with the app version the user actually agreed to.
library;

class LegalSection {
  final String heading;
  final String body;
  const LegalSection(this.heading, this.body);
}

class LegalDocumentContent {
  final String title;
  final String lastUpdated;
  final String intro;
  final List<LegalSection> sections;

  const LegalDocumentContent({
    required this.title,
    required this.lastUpdated,
    required this.intro,
    required this.sections,
  });
}

const termsAndConditions = LegalDocumentContent(
  title: 'Terms & Conditions',
  lastUpdated: '29 October 2026',
  intro:
      'These terms govern your use of Rakan, an adaptive AI fitness coach '
      'developed as a Final Year Project. By creating an account you agree '
      'to them. If you do not agree, do not use the app.',
  sections: [
    LegalSection(
      '1. Eligibility',
      'You must be at least 13 years old to create an account. If you are '
          'under the age of majority where you live, you confirm that a '
          'parent or guardian has agreed to these terms on your behalf.',
    ),
    LegalSection(
      '2. Not medical advice',
      'Rakan provides general fitness guidance only. Workout plans, fatigue '
          'scores, recovery estimates and posture feedback are generated '
          'automatically and are not medical advice, diagnosis or treatment. '
          'Consult a doctor or qualified professional before starting a new '
          'exercise programme, especially if you are injured, pregnant or have '
          'a health condition.',
    ),
    LegalSection(
      '3. Exercise at your own risk',
      'Physical exercise carries a risk of injury. You are responsible for '
          'training within your limits, using equipment safely and stopping '
          'if you feel pain, dizziness or discomfort. Camera-based rep '
          'counting and form feedback can be inaccurate and must not be '
          'relied on as a substitute for your own judgement.',
    ),
    LegalSection(
      '4. Your account',
      'Keep your login details secure and do not share your account. You are '
          'responsible for activity that happens under your account. Provide '
          'accurate information during sign-up and onboarding so your plan '
          'can be adapted correctly.',
    ),
    LegalSection(
      '5. Community conduct',
      'When using social features (profiles, follows, likes and comments) you '
          'agree not to post content that is unlawful, abusive, harassing, '
          'hateful, sexually explicit or that infringes anyone else\'s rights. '
          'Do not impersonate others or upload photos of people without their '
          'consent. We may remove content or suspend accounts that break '
          'these rules.',
    ),
    LegalSection(
      '6. Your content',
      'You keep ownership of the content you add, such as workout logs, '
          'progress photos and comments. You allow Rakan to store and display '
          'it as needed to run the app, including showing it to other users '
          'according to your privacy settings.',
    ),
    LegalSection(
      '7. Availability',
      'Rakan is provided "as is" as a student project. Features may change, '
          'and the service may be unavailable, slow (for example while the '
          'plan server starts up) or discontinued at any time. We do not '
          'guarantee that the app will be error-free.',
    ),
    LegalSection(
      '8. Limitation of liability',
      'To the fullest extent permitted by law, the developers of Rakan are '
          'not liable for any injury, loss or damage arising from your use '
          'of the app or reliance on its recommendations.',
    ),
    LegalSection(
      '9. Ending your account',
      'You can delete your account at any time from Settings. This '
          'permanently removes your profile and data as described in the '
          'Privacy Policy.',
    ),
    LegalSection(
      '10. Changes to these terms',
      'We may update these terms. The "last updated" date above will change '
          'when we do, and continuing to use Rakan after an update means you '
          'accept the revised terms.',
    ),
  ],
);

const privacyPolicy = LegalDocumentContent(
  title: 'Privacy Policy',
  lastUpdated: '29 October 2026',
  intro:
      'This policy explains what information Rakan collects, how it is used '
      'and the choices you have. Rakan is a Final Year Project and only uses '
      'your data to run the app.',
  sections: [
    LegalSection(
      '1. Information you give us',
      '• Account: your email address and password, or your Google account '
          'if you sign in with Google. Passwords are handled by Firebase '
          'Authentication and are never visible to us.\n'
          '• Profile: name, username, gender, age, height, weight, activity '
          'level, goals, experience, training schedule, equipment, '
          'motivation and focus areas.\n'
          '• Health and safety: injuries you mark on the body map and their '
          'recovery progress.\n'
          '• Training: workout logs, sets, reps, weights, effort ratings (RPE), '
          'personal records, body-weight entries and plan changes.\n'
          '• Photos: profile and progress photos you choose to add.\n'
          '• Social: who you follow, follow requests, likes and comments.',
    ),
    LegalSection(
      '2. Camera and voice coaching',
      'Pose detection for rep counting and form feedback runs entirely on '
          'your device. Camera video is processed in real time and is never '
          'recorded, uploaded or stored. Voice coaching is spoken by your '
          'device\'s text-to-speech engine.',
    ),
    LegalSection(
      '3. How we use your information',
      '• To create your account and keep you signed in.\n'
          '• To generate and adapt your workout plan, estimate fatigue and '
          'muscle recovery, and detect plateaus.\n'
          '• To show your stats, history and records.\n'
          '• To power social features such as profiles and activity feeds.\n'
          '• To schedule workout reminders, which are local notifications set '
          'on your device.\n'
          'We do not sell your data, show ads or use your data to train '
          'third-party models.',
    ),
    LegalSection(
      '4. Where your data is stored',
      'Your account and app data are stored in Google Firebase '
          '(Authentication and Cloud Firestore). To generate and adapt your '
          'plan, the app sends the relevant profile and training figures to '
          'Rakan\'s plan server, hosted on Render. The server uses them to '
          'calculate a result and does not keep a separate copy.',
    ),
    LegalSection(
      '5. What other users can see',
      'Your username, display name, profile photo and workout activity can '
          'be seen by other users. Turn on Private Account in Settings to '
          'limit your activity to followers you approve. Your email address, '
          'body measurements and injuries are not shown on your public '
          'profile.',
    ),
    LegalSection(
      '6. Keeping and deleting your data',
      'We keep your data for as long as you have an account. You can edit '
          'your profile and stats at any time, and you can delete your '
          'account from Settings, which permanently deletes your profile, '
          'plans, workout history, photos and followers.',
    ),
    LegalSection(
      '7. Security',
      'Data is sent over encrypted connections and protected by Firebase '
          'security rules so that only you can change your own data. No '
          'system is completely secure, so please use a strong, unique '
          'password.',
    ),
    LegalSection(
      '8. Children',
      'Rakan is not intended for children under 13, and we do not knowingly '
          'collect data from them.',
    ),
    LegalSection(
      '9. Changes to this policy',
      'We may update this policy. The "last updated" date above will change '
          'when we do.',
    ),
  ],
);
