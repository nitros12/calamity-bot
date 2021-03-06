{-# LANGUAGE BlockArguments #-}

-- | Prefix related commands
module CalamityBot.Commands.Prefix
  ( prefixGroup,
  )
where

import Calamity.Commands
import Calamity
import CalamityBot.Db
import Control.Lens hiding (Context)
import qualified Data.Text.Lazy as L
import qualified Polysemy as P
import Relude.Unsafe (fromJust)
import TextShow (TextShow (showtl))
import Database.Beam (runSelectReturningList, runDelete, runInsert, runSelectReturningOne)

guildOnly :: Context -> Maybe L.Text
guildOnly ctx = maybe (Just "Can only be used in guilds") (const Nothing) (ctx ^. #guild)

prefixLimit :: P.Member DBEff r => Integer -> Context -> P.Sem r (Maybe L.Text)
prefixLimit limit ctx =
  case ctx ^. #guild of
    Just g -> do
      np <- fromMaybe 0 <$> usingConn (runSelectReturningOne . countPrefixes $ getID @Guild g)
      pure
        if np > limit
          then Just ("Prefix limit reached (" <> showtl limit <> ")")
          else Nothing
    Nothing -> pure Nothing

maintainGuild :: P.Member DBEff r => Snowflake Guild -> P.Sem r ()
maintainGuild gid = void $ usingConn (runInsert $ addGuild gid)

prefixGroup :: (BotC r, P.Member DBEff r) => P.Sem (DSLState r) ()
prefixGroup = void
  . help (const "Commands related to setting prefixes for the bot")
  . requiresPure [("guildOnly", guildOnly)]
  . groupA "prefix" ["prefixes"]
  $ do
    react @'GuildCreateEvt \(g, _) -> -- TODO move this and maintainGuild
      maintainGuild (getID g)

    requires' "prefixLimit" (prefixLimit 6) $ help (const "Add a new prefix") $
      command @'[Named "prefix" L.Text] "add" \ctx p -> do
        let g = fromJust (ctx ^. #guild)
            gid = getID @Guild g
        maintainGuild gid
        usingConn (runInsert $ addPrefix (gid, p))
        void $ tell @L.Text ctx ("Added prefix: " <> p)

    help (const "Remove a prefix") $
      command @'[Named "prefix" L.Text] "remove" \ctx p -> do
        let g = fromJust (ctx ^. #guild)
        usingConn (runDelete $ removePrefix (getID @Guild g, p))
        void $ tell @L.Text ctx ("Removed prefix (if it existed): " <> p)

    help (const "List prefixes") $
      commandA @'[] "list" ["show"] \ctx -> do
        let g = fromJust (ctx ^. #guild)
            gid = getID @Guild g
        prefixes <- usingConn $ runSelectReturningList (getPrefixes' gid)
        void $ tell @L.Text ctx ("Prefixes: " <> L.unwords (map codeline prefixes))
