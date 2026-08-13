// 2026-08-12: 팀원이 작성한 실제 이메일 인증번호 발송 코드로 교체함 — 콘솔에서 직접 배포하던 걸
// 여기(Terraform 관리, lambda.tf의 archive_file이 이 폴더를 zip으로 패키징)로 옮김.
import {
  SESv2Client,
  SendEmailCommand,
} from "@aws-sdk/client-sesv2";

const sesClient = new SESv2Client({
  region: process.env.AWS_REGION,
});

export const handler = async (event) => {
  console.log("SQS 이벤트:", JSON.stringify(event));

  for (const record of event.Records) {
    const body = JSON.parse(record.body);

    const email = body.email;
    const code = body.code;

    if (!email || !code) {
      throw new Error("email 또는 code가 없습니다.");
    }

    const command = new SendEmailCommand({
      FromEmailAddress: process.env.FROM_EMAIL,

      Destination: {
        ToAddresses: [email],
      },

      Content: {
        Simple: {
          Subject: {
            Data: "[Qket] 이메일 인증번호",
            Charset: "UTF-8",
          },

          Body: {
            Text: {
              Data:
                `Qket 이메일 인증번호입니다.\n\n` +
                `인증번호: ${code}\n\n` +
                `인증번호는 5분 동안 유효합니다.`,
              Charset: "UTF-8",
            },
          },
        },
      },
    });

    const response = await sesClient.send(command);

    console.log("이메일 발송 성공:", {
      email,
      messageId: response.MessageId,
    });
  }
};
