// lib/controller/chatting_viewmodel.dart

import 'package:get/get.dart';
import 'package:palink_v2/controller/tip_viewmodel.dart';
import 'package:palink_v2/models/chat/ai_response.dart';
import 'package:palink_v2/models/chat/message.dart';
import 'package:palink_v2/services/chat_service.dart';
import 'package:palink_v2/services/openai_service.dart';
import 'package:palink_v2/controller/user_controller.dart';
import 'package:flutter/material.dart';
import '../models/character.dart';
import '../models/likability.dart';
import '../models/liking_level.dart';
import '../repository/chat_repository.dart';
import '../utils/message_utils.dart';
import '../views/chatting_view/conversation_end_loading.dart';
class ChatViewModel extends GetxController {
  final int chatRoomId;
  final Character character;
  final OpenAIService openAIService;
  final UserController userController = Get.put(UserController());

  final ChatRepository chatRepository = ChatRepository();
  TextEditingController textController = TextEditingController();

  var messages = <Message>[].obs;
  var isLoading = false.obs;
  var likingLevels = <LikingLevel>[].obs;
  var tipContent = ''.obs;



  ChatViewModel(this.chatRoomId, this.character, this.openAIService);

  @override
  void onInit() {
    super.onInit();
    loadMessages();
  }

  @override
  void onClose() {
    textController.dispose();
    super.onClose();
  }

  Future<void> loadMessages() async {
    isLoading.value = true;
    try {
      List<Message> list = await chatRepository.getMessagesByChatRoomId(chatRoomId);
      messages.value = list;
    } catch (e) {
      print('Failed to load messages: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // 메시지 전송 및 응답 처리 (+호감도, 팁 업데이트)
  Future<void> sendMessage() async {
    String text = textController.text;
    if (text.isEmpty) return;

    try {
      // 사용자 메시지
      Message? sentUserMessage = await chatRepository.sendUserMessage(
          text, chatRoomId);
      if (sentUserMessage != null) {
        messages.insert(0, sentUserMessage); // 사용자 메시지 화면에 표시
        likingLevels.insert(0, LikingLevel(
            likingLevel: 0, messageId: sentUserMessage.messageId)); // 더미 호감도 저장
      }

      // AI 메시지
      AIResponse? aiResponse = await openAIService.invokeChain(
          text); // ai로 text 넣어서 응답받는거
      if (aiResponse != null) {
        MessageDto botMessageDto = MessageUtils.convertAIMessageToMessageDto(
            aiResponse, chatRoomId);
        Message? sentBotMessage = await chatRepository.sendMessage(
            botMessageDto);

        // 여기에 aiResponse의 isEnd 값확인하고, 1이면 종료
        // 대화 종료 체크
        if (aiResponse.isEnd == 1) {
          Get.to(() => ConversationEndLoadingView(character: character));
        }

        print('호감도: ${aiResponse.affinityScore}');

        if (sentBotMessage != null) {
          messages.insert(0, sentBotMessage); // 받은 AI 메시지 화면에 표시
          // ai의 호감도 화면에 표시
          likingLevels.insert(0, LikingLevel(
              likingLevel: aiResponse.affinityScore,
              messageId: sentBotMessage.messageId) as LikingLevel);
          // 호감도 db 서버에 전송하기
          chatRepository.sendLikingLevel(
              userController.userId.value, character.characterId,
              aiResponse.affinityScore, sentBotMessage!.messageId);

          // 팁 업데이트
          Map? tipResponse = await openAIService.invokeTip(aiResponse);
          if (tipResponse != null) {
            tipContent.value = tipResponse['answer'];
          }

        }
      }
    } catch (e) {
      print('Failed to send message: $e');
    } finally {
      textController.clear();
    }
  }

  void analyzeMessage(AIResponse aiResponse) {
    // 메시지 분석
    // 메시지에 대한 호감도 업데이트
  }
}
