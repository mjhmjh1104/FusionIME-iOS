#include "ios/FusionMozc.h"
#include <memory>
#include <string>
#include <vector>
#include "base/system_util.h"
#include "data_manager/data_manager.h"
#include "ios/ios_engine.h"
#include "protocol/commands.pb.h"
#include "protocol/config.pb.h"

namespace {
thread_local std::string error;
struct Candidate { int id; std::string text; std::string reading; std::string annotation; bool focused; };
struct Bridge {
  mozc::ios::IosEngine engine;
  mozc::commands::Command command;
  std::string preedit, committed;
  std::vector<Candidate> candidates;
  int cursor=0;
  explicit Bridge(const char *data):engine(data) {}
  int update(bool ok) {
    preedit.clear(); committed.clear(); candidates.clear(); cursor=0;
    if (!ok || !command.has_output()) return 0;
    const auto &out=command.output();
    if (out.has_result()) committed=out.result().value();
    if (out.has_preedit()) {
      for (const auto &seg:out.preedit().segment()) preedit+=seg.value();
      cursor=out.preedit().cursor();
    }
    if (out.has_all_candidate_words()) {
      for (const auto &candidate:out.all_candidate_words().candidates()) {
        const auto &list=out.all_candidate_words();
        const bool focused=list.has_focused_index() && list.focused_index()==candidates.size();
        candidates.push_back({candidate.id(),candidate.value(),candidate.key(),candidate.annotation().description(),focused});
      }
    }
    return 1;
  }
};
Bridge *bridge(void *p) { return static_cast<Bridge *>(p); }
}
extern "C" {
void *fm_create(const char *data, const char *profile) {
  if (!data || !profile) return nullptr;
  error.clear();
  auto check=mozc::DataManager::CreateFromFile(data);
  if (!check.ok()) { error=std::string(check.status().message()); return nullptr; }
  mozc::SystemUtil::SetUserProfileDirectory(profile);
  auto b=std::make_unique<Bridge>(data);
  if (!b->engine.CreateSession(&b->command)) { error="Mozc CreateSession failed"; return nullptr; }
  fm_configure(b.get(),"QWERTY_JA",0);
  return b.release();
}
void fm_destroy(void *p) { if (p) { auto b=bridge(p); b->engine.DeleteSession(&b->command); delete b; } }
int fm_configure(void *p,const char *layout,int learning) {
  if (!p || !layout) return 0;
  auto b=bridge(p); mozc::config::Config config;
  mozc::ios::IosEngine::FillMobileConfig(&config);
  config.set_incognito_mode(!learning);
  config.set_use_emoji_conversion(false);
  b->engine.SetConfig(config,&b->command);
  return b->update(b->engine.SetMobileRequest(layout,&b->command));
}
int fm_key(void *p,const char *text) {
  if (!p || !text) return 0; auto b=bridge(p);
  return b->update(b->engine.SendKey(text,&b->command));
}
int fm_special(void *p,int key) {
  if (!p) return 0; auto b=bridge(p);
  using K=mozc::commands::KeyEvent;
  static const K::SpecialKey keys[]={K::BACKSPACE,K::SPACE,K::ENTER,K::LEFT,K::RIGHT};
  if (key<0 || key>4) return 0;
  return b->update(b->engine.SendSpecialKey(keys[key],&b->command));
}
int fm_command(void *p,int command,int argument,const char *text) {
  if (!p) return 0; auto b=bridge(p);
  using C=mozc::commands::SessionCommand;
  if (command==6) return b->update(b->engine.ClearUserHistory(&b->command));
  if (command==7) return b->update(b->engine.ImportUserDictionary(text ? text : "",&b->command));
  C c;
  switch(command) {
    case 0: c.set_type(C::RESET_CONTEXT); break;
    case 1: c.set_type(C::SUBMIT); break;
    case 2: c.set_type(C::SUBMIT_CANDIDATE); c.set_id(argument); break;
    case 3: c.set_type(C::DELETE_CANDIDATE_FROM_HISTORY); c.set_id(argument); break;
    case 4: c.set_type(C::CONVERT_REVERSE); c.set_text(text ? text : ""); break;
    case 5: c.set_type(C::STOP_KEY_TOGGLING); break;
    case 8: c.set_type(C::SELECT_CANDIDATE); c.set_id(argument); break;
    case 9: c.set_type(C::MOVE_CURSOR); c.set_cursor_position(argument); break;
    default: return 0;
  }
  return b->update(b->engine.SendSessionCommand(c,&b->command));
}
const char *fm_preedit(void *p) { return p ? bridge(p)->preedit.c_str():""; }
const char *fm_committed(void *p) { return p ? bridge(p)->committed.c_str():""; }
int fm_cursor(void *p) { return p ? bridge(p)->cursor:0; }
int fm_candidate_count(void *p) { return p ? static_cast<int>(bridge(p)->candidates.size()):0; }
int fm_candidate_id(void *p,int i) { return p && i>=0 && i<fm_candidate_count(p) ? bridge(p)->candidates[i].id:-1; }
const char *fm_candidate_text(void *p,int i) { return p && i>=0 && i<fm_candidate_count(p) ? bridge(p)->candidates[i].text.c_str():""; }
const char *fm_candidate_reading(void *p,int i) { return p && i>=0 && i<fm_candidate_count(p) ? bridge(p)->candidates[i].reading.c_str():""; }
const char *fm_candidate_annotation(void *p,int i) { return p && i>=0 && i<fm_candidate_count(p) ? bridge(p)->candidates[i].annotation.c_str():""; }
int fm_candidate_focused(void *p,int i) { return p && i>=0 && i<fm_candidate_count(p) && bridge(p)->candidates[i].focused; }
const char *fm_error(void) { return error.c_str(); }
}
